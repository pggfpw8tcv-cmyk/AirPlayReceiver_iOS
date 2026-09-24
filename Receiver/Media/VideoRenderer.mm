#import "VideoRenderer.h"
#include "MediaPacket.hpp"

@implementation VideoRenderer {
    CMVideoFormatDescriptionRef _format;
    NSData *_sps, *_pps, *_vps;
    BOOL _hevc;
}
- (instancetype)init {
    if ((self = [super init])) {
        _layer = [AVSampleBufferDisplayLayer new];
        _layer.videoGravity = AVLayerVideoGravityResizeAspect;
        CMTimebaseRef timebase = NULL;
        if (CMTimebaseCreateWithSourceClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &timebase) == noErr) {
            CMTimebaseSetTime(timebase, CMClockGetTime(CMClockGetHostTimeClock()));
            CMTimebaseSetRate(timebase, 1.0);
            _layer.controlTimebase = timebase;
            CFRelease(timebase);
        }
    }
    return self;
}
- (void)dealloc { if (_format) CFRelease(_format); }
- (void)flush {
    NSAssert(NSThread.isMainThread, @"Video renderer requires main queue");
    [_layer flushAndRemoveImage];
    if (_format) { CFRelease(_format); _format = NULL; }
    _sps = _pps = _vps = nil;
}
- (BOOL)enqueueAnnexB:(NSData *)data hevc:(BOOL)hevc presentationTime:(uint64_t)hostNanoseconds {
    NSAssert(NSThread.isMainThread, @"Video renderer requires main queue");
    auto units = receiver::splitAnnexB((const uint8_t *)data.bytes, data.length);
    if (units.empty()) return NO;
    if (_hevc != hevc) { [self flush]; _hevc = hevc; }
    BOOL changed = NO, hasPicture = NO;
    std::vector<receiver::NALView> payload;
    for (auto unit : units) {
        if (hevc && unit.size < 2) return NO;
        int type = hevc ? ((unit.data[0] >> 1) & 0x3f) : (unit.data[0] & 0x1f);
        NSData *parameter = [NSData dataWithBytes:unit.data length:unit.size];
        if (type == (hevc ? 33 : 7)) { changed |= ![_sps isEqualToData:parameter]; _sps = parameter; }
        else if (type == (hevc ? 34 : 8)) { changed |= ![_pps isEqualToData:parameter]; _pps = parameter; }
        else if (hevc && type == 32) { changed |= ![_vps isEqualToData:parameter]; _vps = parameter; }
        else {
            payload.push_back(unit);
            hasPicture |= hevc ? type <= 31 : (type >= 1 && type <= 5);
        }
    }
    if (changed && _format) { CFRelease(_format); _format = NULL; [_layer flush]; }
    if (!_format && _sps && _pps && (!hevc || _vps)) {
        OSStatus status;
        if (hevc) {
            const uint8_t *p[] = {(const uint8_t *)_vps.bytes, (const uint8_t *)_sps.bytes, (const uint8_t *)_pps.bytes};
            size_t sizes[] = {_vps.length, _sps.length, _pps.length};
            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault, 3, p, sizes, 4, NULL, &_format);
        } else {
            const uint8_t *p[] = {(const uint8_t *)_sps.bytes, (const uint8_t *)_pps.bytes};
            size_t sizes[] = {_sps.length, _pps.length};
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, p, sizes, 4, &_format);
        }
        if (status != noErr) return NO;
    }
    if (!hasPicture) return YES;
    if (!_format) return NO;
    if (_layer.status == AVQueuedSampleBufferRenderingStatusFailed) [_layer flush];
    if (!_layer.readyForMoreMediaData) return NO;
    auto bytes = receiver::lengthPrefixed(payload);
    if (bytes.empty()) return NO;
    CMBlockBufferRef block = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, bytes.size(),
        kCFAllocatorDefault, NULL, 0, bytes.size(), 0, &block);
    if (status != noErr) return NO;
    status = CMBlockBufferReplaceDataBytes(bytes.data(), block, 0, bytes.size());
    CMSampleBufferRef sample = NULL;
    const size_t size = bytes.size();
    CMSampleTimingInfo timing = {kCMTimeInvalid, CMTimeMake((int64_t)hostNanoseconds, 1000000000), kCMTimeInvalid};
    if (status == noErr)
        status = CMSampleBufferCreateReady(kCFAllocatorDefault, block, _format, 1, 1, &timing, 1, &size, &sample);
    if (status == noErr) { [_layer enqueueSampleBuffer:sample]; CFRelease(sample); }
    CFRelease(block);
    return status == noErr;
}
@end
