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

#import "RHVEngine.h"

#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#import <os/log.h>

#include "core/engine.hpp"
#include "core/document.hpp"
#include "core/voice.hpp"
#include "core/language.hpp"
#include "core/voice_profile.hpp"

#include "OSLogger.hpp"
#include "SampleQueue.hpp"
#include "SpeechSink.hpp"
#include "SSMLNormalizer.hpp"

NSErrorDomain const RHVEngineErrorDomain = @"org.rhvoice.RHVoice.engine";

namespace
{
  os_log_t bridge_log()
  {
    static os_log_t handle = os_log_create("org.rhvoice.RHVoice", "bridge");
    return handle;
  }

  NSError *make_error(RHVEngineError code, NSString *message)
  {
    return [NSError errorWithDomain:RHVEngineErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
  }

  // Everything a request needs, shared by the session object and its synthesis thread so that
  // the thread can outlive the session (cancellation never blocks the caller).
  struct SessionState
  {
    std::shared_ptr<RHVoice::engine> engine;
    std::string original_ssml;
    std::string ssml;
    rhvoice_macos::OffsetMap offsets;
    rhvoice_macos::SampleQueue queue{1u << 17}; // about 5.5 s at 24 kHz
    std::atomic<bool> cancelled{false};
    std::unique_ptr<rhvoice_macos::SpeechSink> sink;
    std::unique_ptr<RHVoice::document> document;
    double sample_rate = 24000;
    std::mutex done_mutex;
    std::condition_variable done_cv;
    bool finished = false;

    void mark_finished()
    {
      std::lock_guard<std::mutex> lock(done_mutex);
      finished = true;
      done_cv.notify_all();
    }
  };
}

@interface RHVSynthesisSession ()
- (instancetype)initWithState:(std::shared_ptr<SessionState>)state;
@end

@implementation RHVVoiceDescriptor
- (instancetype)initWithName:(NSString *)name
                  identifier:(NSString *)identifier
                languageName:(NSString *)languageName
                languageCode:(NSString *)languageCode
               languageCode3:(NSString *)languageCode3
                     country:(NSString *)country
                      gender:(RHVVoiceGender)gender
{
  self = [super init];
  if (self) {
    _name = [name copy];
    _identifier = [identifier copy];
    _languageName = [languageName copy];
    _languageCode = [languageCode copy];
    _languageCode3 = [languageCode3 copy];
    _country = [country copy];
    _gender = gender;
  }
  return self;
}
@end

@implementation RHVSynthesisOptions
- (instancetype)init
{
  self = [super init];
  if (self) {
    _rate = 1.0;
    _pitch = 1.0;
    _volume = 1.0;
    _outputSampleRate = 24000;
  }
  return self;
}
@end

@implementation RHVSynthesisSession {
  std::shared_ptr<SessionState> _state;
}

- (instancetype)initWithState:(std::shared_ptr<SessionState>)state
{
  self = [super init];
  if (self) {
    _state = std::move(state);
  }
  return self;
}

- (double)sampleRate
{
  return _state->sample_rate;
}

- (BOOL)isFinished
{
  std::lock_guard<std::mutex> lock(_state->done_mutex);
  return _state->finished;
}

- (void)cancel
{
  _state->cancelled = true;
  _state->queue.abort();
}

- (RHVRenderStatus)renderInto:(float *)buffer
                   frameCount:(uint32_t)frameCount
          maxWaitMilliseconds:(uint32_t)maxWaitMilliseconds
                framesWritten:(uint32_t *)framesWritten
{
  std::size_t written = 0;
  const auto wait = maxWaitMilliseconds == RHVRenderWaitForever ? std::chrono::milliseconds::max() :
    std::chrono::milliseconds(maxWaitMilliseconds);
  rhvoice_macos::SampleQueue::State state = _state->queue.pop(buffer, frameCount, wait, written);
  if (framesWritten) {
    *framesWritten = static_cast<uint32_t>(written);
  }
  switch (state) {
    case rhvoice_macos::SampleQueue::State::rendering:
      return RHVRenderStatusRendering;
    case rhvoice_macos::SampleQueue::State::complete:
      return RHVRenderStatusComplete;
    case rhvoice_macos::SampleQueue::State::aborted:
      return RHVRenderStatusCancelled;
  }
  return RHVRenderStatusCancelled;
}

- (void)waitUntilFinished
{
  std::unique_lock<std::mutex> lock(_state->done_mutex);
  _state->done_cv.wait(lock, [&] { return _state->finished; });
}

@end

@implementation RHVEngine {
  std::shared_ptr<RHVoice::engine> _engine;
  NSArray<RHVVoiceDescriptor *> *_voices;
  NSString *_version;
  NSLock *_configLock;
}

+ (nullable instancetype)engineWithDataPath:(NSString *)dataPath
                                 configPath:(NSString *)configPath
                                      error:(NSError **)error
{
  RHVoice::engine::init_params params;
  params.data_path = dataPath.UTF8String;
  params.config_path = configPath.UTF8String;
  params.logger = std::make_shared<rhvoice_macos::OSLogger>();
  std::shared_ptr<RHVoice::engine> engine;
  try {
    engine = RHVoice::engine::create(params);
  } catch (const std::exception &e) {
    os_log_error(bridge_log(), "Engine creation failed: %{public}s", e.what());
    if (error) {
      *error = make_error(RHVEngineErrorNoData, [NSString stringWithUTF8String:e.what()]);
    }
    return nil;
  }
  RHVEngine *result = [[RHVEngine alloc] init];
  result->_engine = engine;
  result->_configLock = [[NSLock alloc] init];
  result->_version = [NSString stringWithUTF8String:engine->get_version().c_str()];
  NSMutableArray<RHVVoiceDescriptor *> *voices = [NSMutableArray array];
  const RHVoice::voice_list &list = engine->get_voices();
  for (RHVoice::voice_list::const_iterator it = list.begin(); it != list.end(); ++it) {
    const RHVoice::voice_info &voice = *it;
    RHVoice::language_list::const_iterator language = voice.get_language();
    RHVVoiceGender gender = RHVVoiceGenderUnknown;
    switch (voice.get_gender()) {
      case RHVoice_voice_gender_male: gender = RHVVoiceGenderMale; break;
      case RHVoice_voice_gender_female: gender = RHVVoiceGenderFemale; break;
      default: break;
    }
    [voices addObject:[[RHVVoiceDescriptor alloc] initWithName:[NSString stringWithUTF8String:voice.get_name().c_str()]
                                                    identifier:[NSString stringWithUTF8String:voice.get_id().c_str()]
                                                  languageName:[NSString stringWithUTF8String:language->get_name().c_str()]
                                                  languageCode:[NSString stringWithUTF8String:language->get_alpha2_code().c_str()]
                                                 languageCode3:[NSString stringWithUTF8String:language->get_alpha3_code().c_str()]
                                                       country:[NSString stringWithUTF8String:voice.get_country().c_str()]
                                                        gender:gender]];
  }
  result->_voices = [voices copy];
  os_log_info(bridge_log(), "Engine %{public}@ created with %lu voices from %{public}@", result->_version, (unsigned long)voices.count, dataPath);
  return result;
}

- (NSString *)version
{
  return _version;
}

+ (NSString *)normalizedSSML:(NSString *)ssml
{
  rhvoice_macos::OffsetMap offsets;
  std::string normalized = rhvoice_macos::normalize_ssml(ssml.UTF8String, offsets);
  return [NSString stringWithUTF8String:normalized.c_str()];
}

- (NSArray<RHVVoiceDescriptor *> *)voices
{
  return _voices;
}

- (BOOL)setConfigValue:(NSString *)value forKey:(NSString *)key
{
  [_configLock lock];
  bool ok = false;
  try {
    ok = _engine->configure(key.UTF8String, value.UTF8String);
  } catch (const std::exception &e) {
    os_log_error(bridge_log(), "configure(%{public}@) failed: %{public}s", key, e.what());
  }
  [_configLock unlock];
  return ok ? YES : NO;
}

- (nullable RHVSynthesisSession *)startSessionWithSSML:(NSString *)ssml
                                             voiceName:(NSString *)voiceName
                                               options:(nullable RHVSynthesisOptions *)options
                                         markerHandler:(nullable RHVMarkerHandler)markerHandler
                                                 error:(NSError **)error
{
  auto state = std::make_shared<SessionState>();
  state->engine = _engine;
  if (options) {
    state->sample_rate = options.outputSampleRate;
  }
  try {
    RHVoice::voice_profile profile = _engine->create_voice_profile(voiceName.UTF8String);
    if (profile.empty()) {
      if (error) {
        *error = make_error(RHVEngineErrorVoiceNotFound, [NSString stringWithFormat:@"Voice not found: %@", voiceName]);
      }
      return nil;
    }
    state->original_ssml = ssml.UTF8String;
    state->ssml = rhvoice_macos::normalize_ssml(state->original_ssml, state->offsets);
    try {
      state->document = RHVoice::document::create_from_ssml(_engine, state->ssml.begin(), state->ssml.end(), profile);
    } catch (const std::exception &e) {
      os_log_info(bridge_log(), "SSML parse failed (%{public}s); speaking the request as plain text", e.what());
      state->ssml = state->original_ssml;
      state->offsets = rhvoice_macos::OffsetMap();
      state->document = RHVoice::document::create_from_plain_text(_engine, state->ssml.begin(), state->ssml.end(), RHVoice::content_text, profile);
    }
    if (options) {
      state->document->speech_settings.relative.rate = options.rate;
      state->document->speech_settings.relative.pitch = options.pitch;
      state->document->speech_settings.relative.volume = options.volume;
      if (options.quality.length > 0) {
        state->document->quality.set_from_string(options.quality.UTF8String);
      }
    }
    rhvoice_macos::MarkerCallback markers;
    if (markerHandler) {
      RHVMarkerHandler handler = [markerHandler copy];
      std::weak_ptr<SessionState> weak_state = state;
      markers = [handler, weak_state](rhvoice_macos::MarkerKind kind, std::size_t position, std::size_t length, const std::string &name, uint64_t frame) {
        auto strong = weak_state.lock();
        if (!strong) {
          return;
        }
        std::size_t start = strong->offsets.to_original(position);
        std::size_t end = strong->offsets.to_original(position + length);
        RHVMarkerKind objc_kind = RHVMarkerKindWord;
        switch (kind) {
          case rhvoice_macos::MarkerKind::word: objc_kind = RHVMarkerKindWord; break;
          case rhvoice_macos::MarkerKind::sentence: objc_kind = RHVMarkerKindSentence; break;
          case rhvoice_macos::MarkerKind::bookmark: objc_kind = RHVMarkerKindBookmark; break;
        }
        NSString *bookmark = name.empty() ? nil : [NSString stringWithUTF8String:name.c_str()];
        handler(objc_kind, start, end > start ? end - start : 0, bookmark, frame);
      };
    }
    state->sink.reset(new rhvoice_macos::SpeechSink(state->queue, state->cancelled, state->sample_rate, markers));
    state->document->set_owner(*state->sink);
  } catch (const std::exception &e) {
    os_log_error(bridge_log(), "Request setup failed: %{public}s", e.what());
    if (error) {
      *error = make_error(RHVEngineErrorInvalidInput, [NSString stringWithUTF8String:e.what()]);
    }
    return nil;
  }

  std::thread([state] {
    try {
      state->document->synthesize();
    } catch (const std::exception &e) {
      os_log_error(bridge_log(), "Synthesis failed: %{public}s", e.what());
    } catch (...) {
      os_log_error(bridge_log(), "Synthesis failed with an unknown exception");
    }
    try {
      state->sink->flush();
    } catch (...) {
    }
    state->queue.finish();
    state->mark_finished();
  }).detach();

  return [[RHVSynthesisSession alloc] initWithState:state];
}

@end
