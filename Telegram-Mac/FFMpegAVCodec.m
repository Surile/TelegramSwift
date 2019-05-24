//
//  FFMpegAVCodec.m
//  Telegram
//
//  Created by Mikhail Filimonov on 05/04/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

#import "FFMpegAVCodec.h"

#import "libavcodec/avcodec.h"

@interface FFMpegAVCodec () {
    AVCodec *_impl;
}

@end

@implementation FFMpegAVCodec

- (instancetype)initWithImpl:(AVCodec *)impl {
    self = [super init];
    if (self != nil) {
        _impl = impl;
    }
    return self;
}

+ (FFMpegAVCodec * _Nullable)findForId:(int)codecId {
    AVCodec *codec = avcodec_find_decoder(codecId);
    if (codec) {
        return [[FFMpegAVCodec alloc] initWithImpl:codec];
    } else {
        return nil;
    }
}

- (void *)impl {
    return _impl;
}

@end
