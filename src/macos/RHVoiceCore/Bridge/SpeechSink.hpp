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

#ifndef RHVOICE_MACOS_SPEECH_SINK_HPP
#define RHVOICE_MACOS_SPEECH_SINK_HPP

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "core/client.hpp"
#include "SampleQueue.hpp"

namespace rhvoice_macos
{
  enum class MarkerKind
    {
      word,
      sentence,
      bookmark
    };

  // Called on the synthesis thread. position/length are byte offsets into the UTF-8 text the
  // document was created from; frame is the number of output frames produced so far.
  typedef std::function<void(MarkerKind kind,std::size_t position,std::size_t length,const std::string& name,std::uint64_t frame)> MarkerCallback;

  class Resampler;

  // The RHVoice::client implementation used by the audio unit and the in-app sample player.
  // Converts the engine's 16-bit mono chunks to Float32 at a fixed output rate and pushes them
  // into a SampleQueue; a cancellation flag makes play_speech() return false, which stops the
  // engine at the next chunk boundary.
  class SpeechSink: public RHVoice::client
  {
  public:
    SpeechSink(SampleQueue& queue,std::atomic<bool>& cancelled,double output_sample_rate,MarkerCallback markers);
    ~SpeechSink();

    unsigned int get_audio_buffer_size() const override
    {
      return 20; // milliseconds; keeps cancellation latency at one chunk
    }

    RHVoice::event_mask get_supported_events() const override;
    bool set_sample_rate(int sample_rate) override;
    bool play_speech(const short* samples,std::size_t count) override;
    bool word_starts(std::size_t position,std::size_t length) override;
    bool sentence_starts(std::size_t position,std::size_t length) override;
    bool process_mark(const std::string& name) override;

    // Flushes the resampler tail (if any) into the queue. Call after document::synthesize() returns.
    void flush();

    std::uint64_t frames_produced() const
    {
      return produced;
    }

    int input_sample_rate() const
    {
      return input_rate;
    }

  private:
    SpeechSink(const SpeechSink&)=delete;
    SpeechSink& operator=(const SpeechSink&)=delete;

    bool emit(const float* samples,std::size_t count);
    bool marker(MarkerKind kind,std::size_t position,std::size_t length,const std::string& name);

    SampleQueue& queue;
    std::atomic<bool>& cancelled;
    const double output_rate;
    MarkerCallback markers;
    int input_rate=0;
    std::uint64_t produced=0;
    std::vector<float> scratch;
    std::unique_ptr<Resampler> resampler;
  };
}
#endif
