#ifndef VIDEOMETALVIEW_H
#define VIDEOMETALVIEW_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "api/media_stream_interface.h"

#include <memory>

@class RTCVideoFrame;

@interface VideoMetalView : NSView

@property(nonatomic) CALayerContentsGravity _Nullable videoContentMode;
@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic, nullable) NSValue* rotationOverride;

- (void)setSize:(CGSize)size;
- (void)renderFrame:(nullable RTCVideoFrame *)frame;

- (std::shared_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>>)getSink;

@end

#endif
