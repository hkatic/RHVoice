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

#import <Foundation/Foundation.h>

#import "RHVSynthesisSession.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const RHVEngineErrorDomain;

typedef NS_ERROR_ENUM(RHVEngineErrorDomain, RHVEngineError) {
    RHVEngineErrorNoData = 1,       // no languages/voices found at the data path
    RHVEngineErrorVoiceNotFound,    // the requested voice is not loaded
    RHVEngineErrorInvalidInput,     // the SSML could not be parsed
    RHVEngineErrorInternal
};

typedef NS_ENUM(NSInteger, RHVVoiceGender) {
    RHVVoiceGenderUnknown,
    RHVVoiceGenderMale,
    RHVVoiceGenderFemale
};

/// A voice the engine loaded from the data directory.
NS_SWIFT_SENDABLE
@interface RHVVoiceDescriptor : NSObject
@property (nonatomic, readonly, copy) NSString *name;          // e.g. "Alan"; the value used to select the voice
@property (nonatomic, readonly, copy) NSString *identifier;    // engine id, e.g. "alan"
@property (nonatomic, readonly, copy) NSString *languageName;  // e.g. "English"
@property (nonatomic, readonly, copy) NSString *languageCode;  // ISO 639-1, may be empty
@property (nonatomic, readonly, copy) NSString *languageCode3; // ISO 639-2/3, may be empty
@property (nonatomic, readonly, copy) NSString *country;       // raw engine value ("GBR/GB" style), may be empty
@property (nonatomic, readonly) RHVVoiceGender gender;
@end

/// Per-request settings.
NS_SWIFT_SENDABLE
@interface RHVSynthesisOptions : NSObject
@property (nonatomic) double rate;    // relative multiplier, 1.0 = default
@property (nonatomic) double pitch;   // relative multiplier, 1.0 = default
@property (nonatomic) double volume;  // relative multiplier, 1.0 = default
@property (nonatomic, copy, nullable) NSString *quality; // "max", "standard" or "min"; nil keeps the engine setting
@property (nonatomic) double outputSampleRate; // frames per second delivered by the session, default 24000
@end

/// Wraps one RHVoice::engine. Creation loads the language and voice metadata from dataPath;
/// voice models are loaded lazily on first use.
NS_SWIFT_SENDABLE
@interface RHVEngine : NSObject

/// dataPath must contain languages/ and voices/ subdirectories; configPath must be an existing
/// directory (RHVoice.conf and dicts/ inside it are optional).
+ (nullable instancetype)engineWithDataPath:(NSString *)dataPath
                                 configPath:(NSString *)configPath
                                      error:(NSError **)error;

@property (nonatomic, readonly, copy) NSString *version;
@property (nonatomic, readonly, copy) NSArray<RHVVoiceDescriptor *> *voices;

/// The SSML the engine will actually receive for `ssml` (prosody attributes rewritten into
/// the percentage forms RHVoice understands). Exposed for tests and diagnostics.
+ (NSString *)normalizedSSML:(NSString *)ssml;

/// Sets an engine configuration key, e.g. ("quality", "max") or
/// ("languages.hr.use_pseudo_english", "yes"). Returns NO for unknown keys/values.
- (BOOL)setConfigValue:(NSString *)value forKey:(NSString *)key;

/// Starts synthesizing `ssml` (a complete SSML document; plain text is accepted as a fallback)
/// with the voice whose descriptor name is `voiceName`.
- (nullable RHVSynthesisSession *)startSessionWithSSML:(NSString *)ssml
                                             voiceName:(NSString *)voiceName
                                               options:(nullable RHVSynthesisOptions *)options
                                         markerHandler:(nullable RHVMarkerHandler)markerHandler
                                                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
