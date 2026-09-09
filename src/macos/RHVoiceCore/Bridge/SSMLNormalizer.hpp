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

#ifndef RHVOICE_MACOS_SSML_NORMALIZER_HPP
#define RHVOICE_MACOS_SSML_NORMALIZER_HPP

#include <cstddef>
#include <string>
#include <utility>
#include <vector>

namespace rhvoice_macos
{
  // Maps byte offsets in the normalized SSML string back to the original string.
  // Each entry says: from normalized position `first` onward, original = normalized + `second`.
  class OffsetMap
  {
  public:
    void add(std::size_t normalized_position,long delta)
    {
      entries.emplace_back(normalized_position,delta);
    }

    std::size_t to_original(std::size_t normalized_position) const
    {
      long delta=0;
      for(const auto& e: entries)
        {
          if(e.first<=normalized_position)
            delta=e.second;
          else
            break;
        }
      return static_cast<std::size_t>(static_cast<long>(normalized_position)+delta);
    }

    bool empty() const
    {
      return entries.empty();
    }

  private:
    std::vector<std::pair<std::size_t,long>> entries;
  };

  // RHVoice's SSML prosody handler (src/include/core/ssml.hpp) understands only "default" and
  // percentage values ("150%", "+10%", "-20%"). The system may send any SSML 1.1 form
  // (named values, bare multipliers, semitones, Hz, dB). This rewrites the rate/pitch/volume
  // attributes of every <prosody> element into percentages and records how byte offsets moved,
  // so that word/sentence markers can be mapped back to the original request text.
  // Text content is never modified.
  std::string normalize_ssml(const std::string& ssml,OffsetMap& offsets);

  // Value converters (exposed for unit tests). Return an empty string to keep the value as is.
  std::string normalize_prosody_rate(const std::string& value);
  std::string normalize_prosody_pitch(const std::string& value);
  std::string normalize_prosody_volume(const std::string& value);
}
#endif
