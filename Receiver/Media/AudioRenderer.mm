#import "AudioRenderer.h"
#import <AudioToolbox/AudioToolbox.h>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <memory>
#include <initializer_list>

struct PacketInput {
    const void *bytes; UInt32 length; bool supplied;
    AudioStreamPacketDescription description;
};
static OSStatus supplyPacket(AudioConverterRef, UInt32 *count, AudioBufferList *buffers,
                             AudioStreamPacketDescription **description, void *context) {
    auto *packet = static_cast<PacketInput *>(context);
    if (packet->supplied) { *count = 0; return -1; } // Needs another packet; not end-of-stream.
    packet->supplied = true;
    *count = 1;
    buffers->mNumberBuffers = 1;
    buffers->mBuffers[0] = {2, packet->length, const_cast<void *>(packet->bytes)};
    if (description) *description = &packet->description;
    return noErr;
}

// Wraps a raw AudioSpecificConfig into an MPEG-4 ES_Descriptor (esds payload).
static NSData *esdsCookie(const uint8_t *asc, size_t n) {
    NSMutableData *d = [NSMutableData data];
    auto put = [&](std::initializer_list<uint8_t> bytes) { for (uint8_t b : bytes) [d appendBytes:&b length:1]; };
    const uint8_t decSpecific = 2 + (uint8_t)n;
    const uint8_t decConfig = 13 + decSpecific;
    const uint8_t es = 3 + 2 + decConfig + 3;
    put({0x03, es, 0x00, 0x00, 0x00});
    put({0x04, decConfig, 0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0});
    put({0x05, (uint8_t)n});
    [d appendBytes:asc length:n];
    put({0x06, 0x01, 0x02});
    return d;
}

@implementation AudioRenderer {
    AudioConverterRef _converter;
    AVAudioEngine *_engine;
    AVAudioPlayerNode *_player;
    AVAudioFormat *_format;
    uint32_t _frames;
    uint8_t _compression;
    float _volume;
    std::shared_ptr<std::atomic<int>> _pending;
}
- (instancetype)init {
    if ((self = [super init])) { _volume = 1; _pending = std::make_shared<std::atomic<int>>(0); }
    return self;
}
- (void)dealloc { if (_converter) AudioConverterDispose(_converter); }
- (BOOL)configureCompression:(uint8_t)compression framesPerPacket:(uint32_t)frames error:(NSError **)error {
    [self stop];
    if ((compression != 2 && compression != 4 && compression != 8) || frames == 0 || frames > 4096) {
        if (error) *error = [NSError errorWithDomain:@"ReceiverAudio" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Unsupported audio format"}];
        return NO;
    }
    _frames = frames; _compression = compression;
    AudioStreamBasicDescription input = {};
    input.mSampleRate = 44100; input.mChannelsPerFrame = 2; input.mFramesPerPacket = frames;
    input.mFormatID = compression == 2 ? kAudioFormatAppleLossless : (compression == 8 ? kAudioFormatMPEG4AAC_ELD : kAudioFormatMPEG4AAC);
    if (compression == 2) input.mFormatFlags = kAppleLosslessFormatFlag_16BitSourceData;
    _format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
    OSStatus status = AudioConverterNew(&input, _format.streamDescription, &_converter);
    if (status == noErr && compression == 2) {
        // ALACSpecificConfig (24 bytes), network byte order, matching UxPlay 44.1k/16/stereo.
        uint8_t cookie[] = {0,0,1,0x60,0,16,40,10,14,2,0,255,0,0,0,0,0,0,0,0,0,0,0xac,0x44};
        cookie[0] = frames >> 24; cookie[1] = frames >> 16; cookie[2] = frames >> 8; cookie[3] = frames;
        status = AudioConverterSetProperty(_converter, kAudioConverterDecompressionMagicCookie, sizeof(cookie), cookie);
    }
    // AAC AudioSpecificConfig is needed for the ELD profile (480 vs 512 frame length).
    if (status == noErr && compression != 2) {
        const uint8_t lc[] = {0x12, 0x10};
        const uint8_t eld[] = {0xf8, 0xe8, 0x50, 0x00};
        const uint8_t *asc = compression == 8 ? eld : lc;
        const size_t ascSize = compression == 8 ? sizeof(eld) : sizeof(lc);
        status = AudioConverterSetProperty(_converter, kAudioConverterDecompressionMagicCookie, (UInt32)ascSize, asc);
        if (status != noErr) {
            // Some CoreAudio versions only accept the cookie wrapped as an esds descriptor.
            NSData *esds = esdsCookie(asc, ascSize);
            if (AudioConverterSetProperty(_converter, kAudioConverterDecompressionMagicCookie,
                                          (UInt32)esds.length, esds.bytes) == noErr) status = noErr;
        }
    }
    if (status != noErr) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"audio codec %u (frames %u) rejected, OSStatus %d", compression, frames, (int)status]}];
        [self stop]; return NO;
    }
    _engine = [AVAudioEngine new]; _player = [AVAudioPlayerNode new];
    [_engine attachNode:_player];
    [_engine connect:_player to:_engine.mainMixerNode format:_format];
    _player.volume = _volume;
    [_engine prepare];
    if (![_engine startAndReturnError:error]) { [self stop]; return NO; }
    return YES;
}
- (BOOL)enqueuePacket:(NSData *)data presentationTime:(uint64_t)hostNanoseconds {
    if (!_converter || !_engine.isRunning || data.length == 0 || data.length > 65536 || _pending->load() >= 96) return NO;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_format frameCapacity:4096];
    PacketInput packet = {data.bytes, (UInt32)data.length, false, {0, _frames, (UInt32)data.length}};
    UInt32 count = _frames;
    OSStatus status = AudioConverterFillComplexBuffer(_converter, supplyPacket, &packet, &count, buffer.mutableAudioBufferList, NULL);
    if ((status != noErr && status != -1) || count == 0 || count > buffer.frameCapacity) return NO;
    buffer.frameLength = count;
    const double seconds = double(hostNanoseconds) / 1e9;
    const double latency = AVAudioSession.sharedInstance.outputLatency + AVAudioSession.sharedInstance.IOBufferDuration;
    const uint64_t host = [AVAudioTime hostTimeForSeconds:std::max(0.0, seconds - latency)];
    AVAudioTime *time = [AVAudioTime timeWithHostTime:host];
    auto pending = _pending;
    pending->fetch_add(1);
    [_player scheduleBuffer:buffer atTime:time options:0 completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
        completionHandler:^(AVAudioPlayerNodeCompletionCallbackType) { pending->fetch_sub(1); }];
    if (!_player.isPlaying) [_player play];
    return YES;
}
- (void)setVolumeDecibels:(float)volume {
    if (!std::isfinite(volume)) return;
    _volume = volume <= -144 ? 0 : std::pow(10.0f, std::min(0.0f, volume) / 20.0f);
    _player.volume = _volume;
}
- (void)flush {
    [_player stop];
    _pending = std::make_shared<std::atomic<int>>(0);
    if (_converter) AudioConverterReset(_converter);
}
- (void)stop {
    [self flush]; [_engine stop];
    _player = nil; _engine = nil; _format = nil;
    if (_converter) { AudioConverterDispose(_converter); _converter = NULL; }
}
@end
