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

NS_ASSUME_NONNULL_BEGIN

/// For offline speech rendering: wait for a full buffer, end of stream, or cancellation.
/// Do not use on a real-time audio device callback.
static const uint32_t RHVRenderWaitForever = UINT32_MAX;

typedef NS_ENUM(NSInteger, RHVRenderStatus) {
    RHVRenderStatusRendering,  // more audio may follow
    RHVRenderStatusComplete,   // synthesis finished and every frame was delivered
    RHVRenderStatusCancelled   // cancel was called
};

typedef NS_ENUM(NSInteger, RHVMarkerKind) {
    RHVMarkerKindWord,
    RHVMarkerKindSentence,
    RHVMarkerKindBookmark
};

/// Delivered on the synthesis thread. byteOffset/byteLength address the UTF-8 encoding of the
/// SSML string the session was started with; frameOffset is the number of output frames
/// produced before the marked text starts.
typedef void (^RHVMarkerHandler)(RHVMarkerKind kind, NSUInteger byteOffset, NSUInteger byteLength,
                                 NSString *_Nullable bookmarkName, uint64_t frameOffset);

/// One synthesis request: runs the engine on its own thread and hands out Float32 mono frames
/// at `sampleRate` through `renderInto:...`. Safe to use from any thread.
NS_SWIFT_SENDABLE
@interface RHVSynthesisSession : NSObject

/// Output sample rate of the frames produced by renderInto (always the rate requested at start).
@property (nonatomic, readonly) double sampleRate;

/// YES once the synthesis thread has exited (normally, by error, or after cancel).
@property (nonatomic, readonly, getter=isFinished) BOOL finished;

/// Stops the engine at the next chunk boundary and makes renderInto report cancellation.
- (void)cancel;

/// Fills buffer across synthesis chunks, waiting up to maxWaitMilliseconds for the whole read.
/// Pass RHVRenderWaitForever for offline rendering, or 0 to consume only available frames.
/// End of stream or cancellation can return fewer frames; a finite wait can also time out.
/// The number written is stored in framesWritten; the caller zero-fills the remainder.
/// A zero-frame read only reports the state and never waits.
- (RHVRenderStatus)renderInto:(float *)buffer
                   frameCount:(uint32_t)frameCount
          maxWaitMilliseconds:(uint32_t)maxWaitMilliseconds
                framesWritten:(uint32_t *)framesWritten;

/// Blocks until the synthesis thread has exited. For tests and the command-line tools.
- (void)waitUntilFinished;

@end

NS_ASSUME_NONNULL_END
