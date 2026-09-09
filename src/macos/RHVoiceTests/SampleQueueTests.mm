// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <XCTest/XCTest.h>

#include <future>
#include <numeric>
#include "SampleQueue.hpp"

using rhvoice_macos::SampleQueue;
using namespace std::chrono;

namespace
{
  struct ReadResult
  {
    SampleQueue::State state;
    std::size_t count=0;
    std::vector<float> samples;
  };

  ReadResult read(SampleQueue& queue,std::size_t count,milliseconds wait)
  {
    ReadResult result;
    result.samples.resize(count,-1);
    result.state=queue.pop(result.samples.data(),count,wait,result.count);
    return result;
  }
}

@interface SampleQueueTests : XCTestCase
@end

@implementation SampleQueueTests

- (void)testRenderBufferSpansProducerChunks
{
  SampleQueue queue(1024);
  std::vector<float> input(960);
  std::iota(input.begin(),input.end(),1.0f);
  queue.push(input.data(),480); // RHVoice's 20 ms chunk at 24 kHz
  auto reader=std::async(std::launch::async,[&]{return read(queue,512,milliseconds(1000));});
  // A partially available buffer must not return early and acquire a silent tail.
  XCTAssertTrue(reader.wait_for(milliseconds(20))==std::future_status::timeout);
  queue.push(input.data()+480,480);
  queue.finish();
  const auto first=reader.get();
  XCTAssertEqual(first.count,std::size_t(512));
  XCTAssertTrue(first.state==SampleQueue::State::rendering);
  XCTAssertTrue(std::equal(first.samples.begin(),first.samples.end(),input.begin()));
  const auto last=read(queue,512,milliseconds::max());
  XCTAssertEqual(last.count,std::size_t(448));
  XCTAssertTrue(last.state==SampleQueue::State::complete);
  XCTAssertTrue(std::equal(last.samples.begin(),last.samples.begin()+last.count,input.begin()+512));
  XCTAssertEqual(last.samples[last.count],-1.0f); // only the caller pads the final buffer
}

- (void)testOfflineReadWaitsPastTheOldTimeout
{
  SampleQueue queue(1024);
  std::vector<float> input(512,0.25f);
  queue.push(input.data(),480);
  auto reader=std::async(std::launch::async,[&]{return read(queue,512,milliseconds::max());});
  // Model a synthesis stall longer than both of the old 40/250 ms limits.
  XCTAssertTrue(reader.wait_for(milliseconds(300))==std::future_status::timeout);
  queue.push(input.data()+480,32);
  const auto result=reader.get();
  XCTAssertEqual(result.count,input.size());
  XCTAssertTrue(result.samples==input);
  XCTAssertTrue(result.state==SampleQueue::State::rendering);
}

- (void)testReadsLargerThanQueuePreserveSamplesThroughWraparound
{
  SampleQueue queue(127);
  std::vector<float> input(10000);
  std::iota(input.begin(),input.end(),1.0f);
  auto producer=std::async(std::launch::async,[&]{
    bool pushed=queue.push(input.data(),input.size());
    queue.finish();
    return pushed;
  });
  auto reader=std::async(std::launch::async,[&]{
    std::vector<float> output;
    for(;;)
      {
        const auto result=read(queue,512,milliseconds::max());
        output.insert(output.end(),result.samples.begin(),result.samples.begin()+result.count);
        if(result.state!=SampleQueue::State::rendering)
          return output;
      }
  });
  auto ready=reader.wait_for(seconds(2));
  if(ready!=std::future_status::ready)
    queue.abort(); // also releases the producer if a regression deadlocks the read
  XCTAssertTrue(ready==std::future_status::ready);
  XCTAssertTrue(reader.get()==input);
  XCTAssertTrue(producer.get());
}

- (void)testFiniteWaitReturnsPartialDataAtTheDeadline
{
  SampleQueue queue(1024);
  std::vector<float> input(480,0.5f);
  queue.push(input.data(),input.size());
  const auto start=steady_clock::now();
  const auto result=read(queue,512,milliseconds(30));
  const auto elapsed=steady_clock::now()-start;
  XCTAssertTrue(elapsed>=milliseconds(30));
  XCTAssertTrue(elapsed<seconds(1));
  XCTAssertEqual(result.count,input.size());
  XCTAssertTrue(result.state==SampleQueue::State::rendering);
  XCTAssertTrue(std::equal(input.begin(),input.end(),result.samples.begin()));
}

- (void)testZeroWaitConsumesOnlyAvailableSamples
{
  SampleQueue queue(1024);
  float input=0.5f;
  queue.push(&input,1);
  const auto result=read(queue,512,milliseconds(0));
  XCTAssertEqual(result.count,std::size_t(1));
  XCTAssertEqual(result.samples[0],input);
  XCTAssertTrue(result.state==SampleQueue::State::rendering);
  const auto empty=read(queue,512,milliseconds(0));
  XCTAssertEqual(empty.count,std::size_t(0));
  XCTAssertTrue(empty.state==SampleQueue::State::rendering);
}

- (void)testZeroFrameProbeNeverWaitsOrConsumes
{
  SampleQueue queue(1024);
  auto reader=std::async(std::launch::async,[&]{return read(queue,0,milliseconds::max());});
  const auto ready=reader.wait_for(milliseconds(100));
  if(ready!=std::future_status::ready)
    queue.abort();
  XCTAssertTrue(ready==std::future_status::ready);
  const auto empty=reader.get();
  XCTAssertEqual(empty.count,std::size_t(0));
  XCTAssertTrue(empty.state==SampleQueue::State::rendering);
  float input=0.5f;
  queue.push(&input,1);
  queue.finish();
  XCTAssertTrue(read(queue,0,milliseconds::max()).state==SampleQueue::State::rendering);
  XCTAssertEqual(queue.available(),std::size_t(1));
  XCTAssertTrue(read(queue,1,milliseconds::max()).state==SampleQueue::State::complete);
  XCTAssertTrue(read(queue,0,milliseconds::max()).state==SampleQueue::State::complete);
}

- (void)testFinishWakesEmptyReader
{
  SampleQueue queue(1024);
  auto reader=std::async(std::launch::async,[&]{return read(queue,512,milliseconds::max());});
  queue.finish();
  const auto result=reader.get();
  XCTAssertEqual(result.count,std::size_t(0));
  XCTAssertTrue(result.state==SampleQueue::State::complete);
}

- (void)testCancellationWakesReaderAndDiscardsPartialBuffer
{
  SampleQueue queue(1024);
  float input=0.5f;
  queue.push(&input,1);
  auto reader=std::async(std::launch::async,[&]{return read(queue,512,milliseconds::max());});
  XCTAssertTrue(reader.wait_for(milliseconds(20))==std::future_status::timeout);
  queue.abort();
  XCTAssertTrue(reader.wait_for(seconds(1))==std::future_status::ready);
  const auto result=reader.get();
  XCTAssertEqual(result.count,std::size_t(0));
  XCTAssertTrue(result.state==SampleQueue::State::aborted);
  XCTAssertFalse(queue.push(&input,1));
}

- (void)testCancellationWakesBlockedProducer
{
  SampleQueue queue(1);
  float input=0.5f;
  queue.push(&input,1);
  auto producer=std::async(std::launch::async,[&]{return queue.push(&input,1);});
  XCTAssertTrue(producer.wait_for(milliseconds(20))==std::future_status::timeout);
  queue.abort();
  XCTAssertTrue(producer.wait_for(seconds(1))==std::future_status::ready);
  XCTAssertFalse(producer.get());
  XCTAssertTrue(read(queue,512,milliseconds::max()).state==SampleQueue::State::aborted);
}

@end
