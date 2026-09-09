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

#import <AVFoundation/AVFoundation.h>

#include <cstring>

#include "SpeechSink.hpp"

namespace rhvoice_macos
{
  // Sample-rate converter used only when a voice reports a rate other than the output rate
  // (voices without a 24000/ model directory, or the "min" quality setting).
  class Resampler
  {
  public:
    Resampler(double input_rate,double output_rate):
      ratio(output_rate/input_rate)
    {
      input_format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:input_rate channels:1];
      output_format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:output_rate channels:1];
      converter=[[AVAudioConverter alloc] initFromFormat:input_format toFormat:output_format];
      converter.sampleRateConverterQuality=AVAudioQualityMax;
    }

    // Converts count input samples (or drains the converter when end is true) and appends the
    // result to out. Returns false on a converter error.
    bool convert(const float* samples,std::size_t count,bool end,std::vector<float>& out)
    {
      // Converter internals create autoreleased objects for every chunk. Drain
      // them here rather than retaining them for a potentially long utterance.
      @autoreleasepool {
      AVAudioPCMBuffer* input=nil;
      if(count>0)
        {
          input=[[AVAudioPCMBuffer alloc] initWithPCMFormat:input_format frameCapacity:static_cast<AVAudioFrameCount>(count)];
          std::memcpy(input.floatChannelData[0],samples,count*sizeof(float));
          input.frameLength=static_cast<AVAudioFrameCount>(count);
        }
      AVAudioFrameCount capacity=static_cast<AVAudioFrameCount>(count*ratio)+256;
      AVAudioPCMBuffer* output=[[AVAudioPCMBuffer alloc] initWithPCMFormat:output_format frameCapacity:capacity];
      __block bool supplied=false;
      NSError* error=nil;
      AVAudioConverterOutputStatus status=[converter convertToBuffer:output error:&error withInputFromBlock:^AVAudioBuffer* _Nullable(AVAudioPacketCount packets,AVAudioConverterInputStatus* _Nonnull input_status){
          (void)packets;
          if(supplied||(input==nil))
            {
              *input_status=end?AVAudioConverterInputStatus_EndOfStream:AVAudioConverterInputStatus_NoDataNow;
              return nil;
            }
          supplied=true;
          *input_status=AVAudioConverterInputStatus_HaveData;
          return input;
        }];
      if(status==AVAudioConverterOutputStatus_Error)
        return false;
      const float* data=output.floatChannelData[0];
      out.insert(out.end(),data,data+output.frameLength);
      return true;
      }
    }

  private:
    AVAudioFormat* input_format;
    AVAudioFormat* output_format;
    AVAudioConverter* converter;
    const double ratio;
  };

  SpeechSink::SpeechSink(SampleQueue& queue_,std::atomic<bool>& cancelled_,double output_sample_rate,MarkerCallback markers_):
    queue(queue_),
    cancelled(cancelled_),
    output_rate(output_sample_rate),
    markers(std::move(markers_))
  {
  }

  SpeechSink::~SpeechSink()
  {
  }

  RHVoice::event_mask SpeechSink::get_supported_events() const
  {
    if(!markers)
      return 0;
    return RHVoice::event_word_starts|RHVoice::event_sentence_starts|RHVoice::event_mark;
  }

  bool SpeechSink::set_sample_rate(int sample_rate)
  {
    if(cancelled)
      return false;
    input_rate=sample_rate;
    if(static_cast<double>(sample_rate)!=output_rate)
      resampler.reset(new Resampler(sample_rate,output_rate));
    else
      resampler.reset();
    return true;
  }

  bool SpeechSink::play_speech(const short* samples,std::size_t count)
  {
    if(cancelled)
      return false;
    scratch.resize(count);
    for(std::size_t i=0;i<count;++i)
      scratch[i]=static_cast<float>(samples[i])/32768.0f;
    if(resampler)
      {
        std::vector<float> converted;
        if(!resampler->convert(scratch.data(),count,false,converted))
          return false;
        return emit(converted.data(),converted.size());
      }
    return emit(scratch.data(),count);
  }

  bool SpeechSink::emit(const float* samples,std::size_t count)
  {
    if(count==0)
      return !cancelled;
    if(!queue.push(samples,count))
      return false;
    produced+=count;
    return !cancelled;
  }

  void SpeechSink::flush()
  {
    if(!resampler)
      return;
    std::vector<float> tail;
    if(resampler->convert(nullptr,0,true,tail))
      emit(tail.data(),tail.size());
  }

  bool SpeechSink::marker(MarkerKind kind,std::size_t position,std::size_t length,const std::string& name)
  {
    if(cancelled)
      return false;
    if(markers)
      markers(kind,position,length,name,produced);
    return !cancelled;
  }

  bool SpeechSink::word_starts(std::size_t position,std::size_t length)
  {
    return marker(MarkerKind::word,position,length,std::string());
  }

  bool SpeechSink::sentence_starts(std::size_t position,std::size_t length)
  {
    return marker(MarkerKind::sentence,position,length,std::string());
  }

  bool SpeechSink::process_mark(const std::string& name)
  {
    return marker(MarkerKind::bookmark,0,0,name);
  }
}
