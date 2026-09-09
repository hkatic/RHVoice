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

#ifndef RHVOICE_MACOS_SAMPLE_QUEUE_HPP
#define RHVOICE_MACOS_SAMPLE_QUEUE_HPP

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <mutex>
#include <vector>

namespace rhvoice_macos
{
  // Bounded single-producer/single-consumer queue of Float32 samples.
  //
  // Producer: the synthesis thread (SpeechSink::play_speech), which blocks while the queue
  // is full so that long utterances never accumulate unbounded audio in memory.
  // Consumer: the audio unit render call, which may wait briefly for the first samples of
  // a request so the audio stream does not start with silence.
  class SampleQueue
  {
  public:
    enum class State
      {
        rendering, // more samples may follow
        complete,  // producer finished and every sample was consumed
        aborted    // abort() was called (cancellation)
      };

    explicit SampleQueue(std::size_t capacity):
      buffer(capacity),
      capacity(capacity)
    {
    }

    // Appends samples, blocking while the queue is full. Returns false once abort() was called.
    bool push(const float* samples, std::size_t count)
    {
      std::unique_lock<std::mutex> lock(mutex);
      std::size_t offset=0;
      while(offset<count)
        {
          not_full.wait(lock,[&]{return aborted||(size<capacity);});
          if(aborted)
            return false;
          std::size_t n=std::min(count-offset,capacity-size);
          for(std::size_t i=0;i<n;++i)
            {
              buffer[tail]=samples[offset+i];
              tail=(tail+1)%capacity;
            }
          size+=n;
          offset+=n;
          not_empty.notify_one();
        }
      return true;
    }

    // Marks the end of the stream. Once the remaining samples are consumed, pop() reports complete.
    void finish()
    {
      std::lock_guard<std::mutex> lock(mutex);
      finished=true;
      not_empty.notify_all();
    }

    // Cancels the stream: wakes every waiter, push() fails and pop() reports aborted.
    void abort()
    {
      std::lock_guard<std::mutex> lock(mutex);
      aborted=true;
      not_empty.notify_all();
      not_full.notify_all();
    }

    // Copies up to max_count samples into out and stores the number copied in count_out.
    // When nothing is available and the stream is still open, waits up to max_wait first.
    State pop(float* out,std::size_t max_count,std::chrono::milliseconds max_wait,std::size_t& count_out)
    {
      std::unique_lock<std::mutex> lock(mutex);
      if((size==0)&&!finished&&!aborted&&(max_wait.count()>0))
        not_empty.wait_for(lock,max_wait,[&]{return (size>0)||finished||aborted;});
      if(aborted)
        {
          count_out=0;
          return State::aborted;
        }
      std::size_t n=std::min(max_count,size);
      for(std::size_t i=0;i<n;++i)
        {
          out[i]=buffer[head];
          head=(head+1)%capacity;
        }
      size-=n;
      count_out=n;
      if(n>0)
        not_full.notify_one();
      if(finished&&(size==0))
        return State::complete;
      return State::rendering;
    }

    std::size_t available() const
    {
      std::lock_guard<std::mutex> lock(mutex);
      return size;
    }

    bool is_finished() const
    {
      std::lock_guard<std::mutex> lock(mutex);
      return finished;
    }

    bool is_aborted() const
    {
      std::lock_guard<std::mutex> lock(mutex);
      return aborted;
    }

  private:
    SampleQueue(const SampleQueue&)=delete;
    SampleQueue& operator=(const SampleQueue&)=delete;

    std::vector<float> buffer;
    const std::size_t capacity;
    std::size_t head=0,tail=0,size=0;
    bool finished=false,aborted=false;
    mutable std::mutex mutex;
    std::condition_variable not_empty,not_full;
  };
}
#endif
