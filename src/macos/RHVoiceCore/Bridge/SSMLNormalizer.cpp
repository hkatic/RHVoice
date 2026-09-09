// Copyright (C) 2026 RHVoice contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 2.1 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#include "SSMLNormalizer.hpp"

#include <cctype>
#include <cmath>
#include <cstdlib>
#include <map>

namespace rhvoice_macos
{
  namespace
  {
    std::string trim(const std::string& s)
    {
      std::size_t b=0,e=s.size();
      while((b<e)&&std::isspace(static_cast<unsigned char>(s[b])))
        ++b;
      while((e>b)&&std::isspace(static_cast<unsigned char>(s[e-1])))
        --e;
      return s.substr(b,e-b);
    }

    std::string lower(std::string s)
    {
      for(auto& c: s)
        c=static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
      return s;
    }

    std::string percent(double value,double min_value,double max_value)
    {
      if(value<min_value)
        value=min_value;
      if(value>max_value)
        value=max_value;
      return std::to_string(static_cast<long>(std::lround(value)))+"%";
    }

    // Parses "[+|-]number[unit]". Returns false if the value does not start with a number.
    bool parse_number(const std::string& value,int& sign,double& number,std::string& unit)
    {
      std::string v=trim(value);
      if(v.empty())
        return false;
      sign=0;
      std::size_t pos=0;
      if(v[0]=='+')
        {
          sign=1;
          pos=1;
        }
      else if(v[0]=='-')
        {
          sign=-1;
          pos=1;
        }
      const char* start=v.c_str()+pos;
      char* end=nullptr;
      number=std::strtod(start,&end);
      if(end==start)
        return false;
      unit=lower(trim(std::string(end)));
      return true;
    }

    bool is_plain_percent(int sign,const std::string& unit)
    {
      (void)sign;
      return unit=="%";
    }

    const std::map<std::string,double> rate_names={{"x-slow",50},{"slow",75},{"medium",100},{"fast",150},{"x-fast",200}};
    const std::map<std::string,double> pitch_names={{"x-low",60},{"low",80},{"medium",100},{"high",125},{"x-high",150}};
    const std::map<std::string,double> volume_names={{"silent",1},{"x-soft",25},{"soft",50},{"medium",100},{"loud",150},{"x-loud",200}};
  }

  std::string normalize_prosody_rate(const std::string& value)
  {
    std::string v=lower(trim(value));
    if(v.empty()||(v=="default"))
      return std::string();
    auto named=rate_names.find(v);
    if(named!=rate_names.end())
      return percent(named->second,10,500);
    int sign;
    double number;
    std::string unit;
    if(!parse_number(v,sign,number,unit))
      return std::string();
    if(is_plain_percent(sign,unit))
      return std::string();
    if(unit.empty()||(unit=="x"))
      {
        // Bare multiplier: 1.0 = normal. A signed bare number is a relative multiplier.
        if(sign==0)
          return percent(number*100,10,500);
        return percent((1.0+sign*number)*100,10,500);
      }
    return std::string();
  }

  std::string normalize_prosody_pitch(const std::string& value)
  {
    std::string v=lower(trim(value));
    if(v.empty()||(v=="default"))
      return std::string();
    auto named=pitch_names.find(v);
    if(named!=pitch_names.end())
      return percent(named->second,50,200);
    int sign;
    double number;
    std::string unit;
    if(!parse_number(v,sign,number,unit))
      return std::string();
    if(is_plain_percent(sign,unit))
      return std::string();
    if(unit=="st")
      {
        // Semitones, always relative in SSML.
        double semitones=(sign==0)?number:(sign*number);
        return percent(std::pow(2.0,semitones/12.0)*100,50,200);
      }
    if(unit=="hz")
      {
        // No absolute reference exists for an HMM voice; treat 110 Hz as the nominal baseline.
        const double baseline=110.0;
        double hz=(sign==0)?number:(baseline+sign*number);
        return percent(hz/baseline*100,50,200);
      }
    if(unit.empty()||(unit=="x"))
      {
        if(sign==0)
          return percent(number*100,50,200);
        return percent((1.0+sign*number)*100,50,200);
      }
    return std::string();
  }

  std::string normalize_prosody_volume(const std::string& value)
  {
    std::string v=lower(trim(value));
    if(v.empty()||(v=="default"))
      return std::string();
    auto named=volume_names.find(v);
    if(named!=volume_names.end())
      return percent(named->second,1,200);
    int sign;
    double number;
    std::string unit;
    if(!parse_number(v,sign,number,unit))
      return std::string();
    if(is_plain_percent(sign,unit))
      {
        // RHVoice ignores a value of zero entirely; make "0%" audible-silent instead.
        if((sign==0)&&(number==0))
          return "1%";
        return std::string();
      }
    if(unit=="db")
      {
        double db=(sign==0)?number:(sign*number);
        return percent(std::pow(10.0,db/20.0)*100,1,200);
      }
    if(unit.empty())
      {
        // SSML 1.0 absolute scale 0..100 (100 = full volume).
        if(sign==0)
          return percent(number==0?1:number,1,200);
        return percent((1.0+sign*number/100.0)*100,1,200);
      }
    return std::string();
  }

  std::string normalize_ssml(const std::string& ssml,OffsetMap& offsets)
  {
    std::string out;
    out.reserve(ssml.size());
    long delta=0; // original - normalized, for positions at/after the last rewrite
    std::size_t pos=0;
    while(pos<ssml.size())
      {
        std::size_t tag=ssml.find("<prosody",pos);
        if(tag==std::string::npos)
          {
            out.append(ssml,pos,std::string::npos);
            break;
          }
        std::size_t tag_end=ssml.find('>',tag);
        if(tag_end==std::string::npos)
          {
            out.append(ssml,pos,std::string::npos);
            break;
          }
        // Copy everything up to the tag verbatim, then rewrite the tag's attributes.
        out.append(ssml,pos,tag-pos);
        std::size_t i=tag;
        while(i<=tag_end)
          {
            // Look for name="value" or name='value' with one of the three prosody attributes.
            std::size_t eq=ssml.find('=',i);
            if((eq==std::string::npos)||(eq>tag_end))
              {
                out.append(ssml,i,tag_end-i+1);
                break;
              }
            // Attribute name: the identifier immediately before '='.
            std::size_t name_end=eq;
            while((name_end>i)&&std::isspace(static_cast<unsigned char>(ssml[name_end-1])))
              --name_end;
            std::size_t name_start=name_end;
            while((name_start>i)&&(std::isalnum(static_cast<unsigned char>(ssml[name_start-1]))||(ssml[name_start-1]=='-')||(ssml[name_start-1]==':')))
              --name_start;
            std::string name=lower(ssml.substr(name_start,name_end-name_start));
            std::size_t q=eq+1;
            while((q<tag_end)&&std::isspace(static_cast<unsigned char>(ssml[q])))
              ++q;
            if((q>=tag_end)||((ssml[q]!='"')&&(ssml[q]!='\'')))
              {
                out.append(ssml,i,eq+1-i);
                i=eq+1;
                continue;
              }
            char quote=ssml[q];
            std::size_t value_start=q+1;
            std::size_t value_end=ssml.find(quote,value_start);
            if((value_end==std::string::npos)||(value_end>tag_end))
              {
                out.append(ssml,i,tag_end-i+1);
                break;
              }
            std::string value=ssml.substr(value_start,value_end-value_start);
            std::string replacement;
            if(name=="rate")
              replacement=normalize_prosody_rate(value);
            else if(name=="pitch")
              replacement=normalize_prosody_pitch(value);
            else if(name=="volume")
              replacement=normalize_prosody_volume(value);
            out.append(ssml,i,value_start-i);
            if(replacement.empty())
              out.append(value);
            else
              {
                out.append(replacement);
                delta+=static_cast<long>(value.size())-static_cast<long>(replacement.size());
                offsets.add(out.size(),delta);
              }
            i=value_end;
          }
        pos=tag_end+1;
      }
    return out;
  }
}
