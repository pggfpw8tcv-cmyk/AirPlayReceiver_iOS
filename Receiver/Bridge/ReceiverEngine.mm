#import "ReceiverEngine.h"
#import "Bonjour.h"
#import "VideoRenderer.h"
#import "AudioRenderer.h"
#include "raop.h"
#include "Clock.hpp"
#include "MediaPacket.hpp"
#include "PTPProbe.hpp"
#include <atomic>
#include <cstring>
#include <mutex>
#include <set>
#include <string>

@interface ReceiverEngine ()
- (void)receiveVideo:(video_decode_struct *)packet;
- (void)receiveAudio:(audio_decode_struct *)packet;
- (void)configureAudio:(uint8_t)compression frames:(uint32_t)frames;
- (void)flushVideo;
- (void)flushAudio;
- (void)endStream;
- (void)postPIN:(NSString *)pin;
- (void)postDiagnostic:(NSString *)text;
- (void)saveClient:(const char *)key;
- (BOOL)knownClient:(const char *)key;
- (void)fail:(NSString *)message generation:(uint64_t)generation;
- (void)markReceiving;
- (void)stopWithStatus:(NSString *)status;
@end

static ReceiverEngine *owner(void *cls) { return (__bridge ReceiverEngine *)cls; }
// The sender timestamps (ntp_time_local) are NOT on the iPad's wall clock (observed: tiny values),
// so instead of trusting an absolute base we anchor the first packet to "host now + latency" and
// keep that offset for audio and video alike, which preserves A/V sync.
static std::mutex gAnchorMutex;
static bool gAnchored = false;
static int64_t gAnchorOffset = 0;
static void resetPresentationAnchor() {
    std::lock_guard<std::mutex> lock(gAnchorMutex);
    gAnchored = false;
}
static std::optional<uint64_t> presentation(uint64_t pts) {
    const int64_t now = (int64_t)CMTimeConvertScale(CMClockGetTime(CMClockGetHostTimeClock()), 1000000000, kCMTimeRoundingMethod_Default).value;
    const int64_t latency = 200000000; // 200 ms jitter buffer
    if (pts == 0 || pts > (uint64_t)INT64_MAX / 2) return (uint64_t)(now + latency);
    std::lock_guard<std::mutex> lock(gAnchorMutex);
    int64_t target = 0;
    if (gAnchored) {
        target = (int64_t)pts + gAnchorOffset;
        // Clock jump or long pause: start over instead of playing garbage.
        if (target < now - 1000000000LL || target > now + 3000000000LL) gAnchored = false;
    }
    if (!gAnchored) {
        gAnchorOffset = now + latency - (int64_t)pts;
        gAnchored = true;
        target = now + latency;
    }
    return (uint64_t)target;
}

@implementation ReceiverEngine {
    VideoRenderer *_video;
    AudioRenderer *_audio;
    dispatch_queue_t _controlQueue, _audioQueue;
    raop_t *_raop;
    dnssd_t *_dnssd;
    std::atomic<bool> _active, _receiving;
    std::atomic<uint64_t> _generation, _videoGeneration, _audioGeneration;
    std::atomic<int> _videoPending, _audioPending;
    std::atomic<int> _videoLogCount, _audioLogCount;
    std::mutex _clientsMutex;
    std::set<std::string> _clients;
    NSURL *_clientsURL;
    NSMutableSet<NSString *> *_published;
    BOOL _stopping;
}
- (instancetype)init {
    if ((self = [super init])) {
        _video = [VideoRenderer new]; _audio = [AudioRenderer new];
        _controlQueue = dispatch_queue_create("receiver.control", DISPATCH_QUEUE_SERIAL);
        _audioQueue = dispatch_queue_create("receiver.audio", DISPATCH_QUEUE_SERIAL);
        _active = false; _receiving = false; _generation = 0;
        _videoGeneration = 0; _audioGeneration = 0; _videoPending = 0; _audioPending = 0;
        _published = [NSMutableSet set];
    }
    return self;
}
- (AVSampleBufferDisplayLayer *)displayLayer { return _video.layer; }
- (void)postDiagnostic:(NSString *)text {
    const auto generation = _generation.load();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == self->_generation.load()) [self.delegate receiverDiagnostic:text];
    });
}
- (void)postPIN:(NSString *)pin {
    const auto generation = _generation.load();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_active && generation == self->_generation.load()) [self.delegate receiverPIN:pin];
    });
}
- (void)saveClient:(const char *)key {
    if (!key || strlen(key) > 1024) return;
    std::lock_guard<std::mutex> lock(_clientsMutex);
    if (_clients.size() >= 256) return;
    _clients.insert(key);
    NSMutableArray *keys = [NSMutableArray array];
    for (const auto& item : _clients) [keys addObject:[NSString stringWithUTF8String:item.c_str()]];
    [keys writeToURL:_clientsURL atomically:YES];
}
- (BOOL)knownClient:(const char *)key {
    if (!key) return NO;
    std::lock_guard<std::mutex> lock(_clientsMutex);
    return _clients.count(key) != 0;
}
- (void)startWithName:(NSString *)name identity:(NSData *)identity storageURL:(NSURL *)storage requirePIN:(BOOL)requirePIN {
    NSAssert(NSThread.isMainThread, @"Control from main queue");
    if (_stopping) return;
    if (_active.exchange(true)) return;
    if (identity.length != 6 || name.length == 0 || [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 50 ||
        [name containsString:@".local"] || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        _active = false;
        [self.delegate receiverStatus:@"Der Empfängername darf höchstens 50 Bytes lang sein (ohne .local und Steuerzeichen)." active:NO];
        return;
    }
    const auto generation = ++_generation;
    _videoLogCount = 0; _audioLogCount = 0;
    resetPresentationAnchor();
    [_published removeAllObjects];
    [self.delegate receiverStatus:@"Wird gestartet…" active:YES];
    dispatch_async(_controlQueue, ^{
        @autoreleasepool {
            NSError *error = nil;
            if (![NSFileManager.defaultManager createDirectoryAtURL:storage withIntermediateDirectories:YES attributes:nil error:&error]) {
                [self fail:error.localizedDescription generation:generation]; return;
            }
            self->_clientsURL = [storage URLByAppendingPathComponent:@"paired-clients.plist"];
            {
                std::lock_guard<std::mutex> lock(self->_clientsMutex);
                self->_clients.clear();
                NSArray *saved = [NSArray arrayWithContentsOfURL:self->_clientsURL];
                for (id key in saved) if ([key isKindOfClass:NSString.class] && [key length] <= 1024 && self->_clients.size() < 256)
                    self->_clients.insert([key UTF8String]);
            }
            AVAudioSession *session = AVAudioSession.sharedInstance;
            if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error] ||
                ![session setActive:YES error:&error]) {
                [self fail:error.localizedDescription generation:generation]; return;
            }
            raop_callbacks_t callbacks = {};
            callbacks.cls = (__bridge void *)self;
            callbacks.video_process = [](void *c, raop_ntp_t *, video_decode_struct *d) { @autoreleasepool { [owner(c) receiveVideo:d]; } };
            callbacks.audio_process = [](void *c, raop_ntp_t *, audio_decode_struct *d) { @autoreleasepool { [owner(c) receiveAudio:d]; } };
            callbacks.audio_get_format = [](void *c, unsigned char *ct, unsigned short *spf, bool *, bool *, uint64_t *) {
                @autoreleasepool { [owner(c) configureAudio:*ct frames:*spf]; }
            };
            callbacks.audio_flush = [](void *c) { [owner(c) flushAudio]; };
            callbacks.video_flush = [](void *c) { [owner(c) flushVideo]; };
            callbacks.video_reset = [](void *c, reset_type_t) { [owner(c) endStream]; };
            callbacks.conn_reset = [](void *c, int) { [owner(c) endStream]; };
            callbacks.conn_init = [](void *) {};
            callbacks.conn_destroy = [](void *) {};
            callbacks.conn_feedback = [](void *) {};
            callbacks.video_pause = [](void *c) { [owner(c) flushVideo]; };
            callbacks.video_resume = [](void *) {};
            callbacks.video_report_size = [](void *, float *, float *, float *, float *) {};
            callbacks.video_set_codec = [](void *, video_codec_t codec) { return codec == VIDEO_CODEC_H264 || codec == VIDEO_CODEC_H265 ? 0 : -1; };
            callbacks.audio_set_client_volume = [](void *) -> double { return 0.0; };
            callbacks.audio_set_volume = [](void *c, float volume) {
                ReceiverEngine *engine = owner(c);
                dispatch_async(engine->_audioQueue, ^{ [engine->_audio setVolumeDecibels:volume]; });
            };
            callbacks.audio_set_metadata = [](void *, const void *, int) {};
            callbacks.audio_set_coverart = [](void *, const void *, int) {};
            callbacks.audio_stop_coverart_rendering = [](void *) {};
            callbacks.audio_set_progress = [](void *, uint32_t *, uint32_t *, uint32_t *) {};
            callbacks.audio_remote_control_id = [](void *, const char *, const char *) {};
            callbacks.export_dacp = [](void *, const char *, const char *) {};
            callbacks.display_pin = [](void *c, char *pin) { @autoreleasepool { if (pin) [owner(c) postPIN:[NSString stringWithUTF8String:pin]]; } };
            callbacks.register_client = [](void *c, const char *, const char *key, const char *) { @autoreleasepool { [owner(c) saveClient:key]; } };
            callbacks.check_register = [](void *c, const char *key) -> bool { return [owner(c) knownClient:key]; };
            callbacks.report_client_request = [](void *, char *, char *, char *, bool *admit) { *admit = true; };
            callbacks.passwd = [](void *, int *length) -> const char * { *length = 0; return nullptr; };
            // HLS isn't advertised. Defensive callbacks reject unsolicited HLS controls safely.
            callbacks.on_video_play = [](void *c, const char *, float) { [owner(c) postDiagnostic:@"HLS-Videoübertragung ist nicht implementiert. Bitte die Bildschirmspiegelung verwenden."]; };
            callbacks.on_video_scrub = [](void *, float) {};
            callbacks.on_video_rate = [](void *, float) {};
            callbacks.on_video_stop = [](void *) {};
            callbacks.on_video_playlist_remove = [](void *) -> float { return 0; };
            callbacks.on_video_acquire_playback_info = [](void *, playback_info_t *info) { memset(info, 0, sizeof(*info)); };

            int dnsError = 0;
            self->_dnssd = dnssd_init(name.UTF8String, (int)[name lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
                (const char *)identity.bytes, 6, requirePIN ? 1 : 0, &dnsError);
            if (!self->_dnssd) { [self fail:@"Bonjour-Initialisierung fehlgeschlagen." generation:generation]; return; }
            // Preserve upstream authentication/audio bits; remove unimplemented media/metadata.
            const int disabled[] = {0,1,2,3,4,5,13,15,16,17,40,41,42,46,48,50,51,52,54};
            for (int bit : disabled) dnssd_set_airplay_features(self->_dnssd, bit, 0);
            self->_raop = raop_init(&callbacks);
            if (!self->_raop) { [self fail:@"Initialisierung des Empfängerkerns fehlgeschlagen." generation:generation]; return; }
            // Do not enable upstream raw-packet logging (may contain credentials or media).
            raop_set_log_level(self->_raop, 0);
            const unsigned char *mac = (const unsigned char *)identity.bytes;
            NSString *device = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]];
            NSURL *key = [storage URLByAppendingPathComponent:@"receiver.key"];
            if (raop_init2(self->_raop, 0, device.UTF8String, key.fileSystemRepresentation) != 0) {
                [self fail:@"Initialisierung des Empfängerschlüssels fehlgeschlagen." generation:generation]; return;
            }
            raop_set_dnssd(self->_raop, self->_dnssd);
            raop_set_plist(self->_raop, "width", 1920);
            raop_set_plist(self->_raop, "height", 1080);
            raop_set_plist(self->_raop, "maxFPS", 30);
            if (requirePIN) raop_set_plist(self->_raop, "pin", 1);
            __weak ReceiverEngine *weakSelf = self;
            ReceiverBonjourSetHandler(self->_dnssd, ^(NSString *type, NSError *publishError) {
                ReceiverEngine *engine = weakSelf;
                if (!engine || !engine->_active || generation != engine->_generation.load()) return;
                if (publishError) { [engine stopWithStatus:publishError.localizedDescription]; return; }
                [engine->_published addObject:type];
                if (engine->_published.count == 2 && !engine->_receiving) [engine.delegate receiverStatus:@"Wartet auf Verbindung" active:YES];
            });
            unsigned short port = 0;
            if (raop_start_httpd(self->_raop, &port) < 0 || !port) { [self fail:@"Empfangsport kann nicht geöffnet werden." generation:generation]; return; }
            raop_set_port(self->_raop, port);
            dnssd_register_raop(self->_dnssd, port);
            dnssd_register_airplay(self->_dnssd, port);
            [self postDiagnostic:[NSString stringWithFormat:@"Empfangsport: %u / UxPlay-Kern", port]];
        }
    });
}
- (void)fail:(NSString *)message generation:(uint64_t)generation {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self->_generation.load()) return;
        [self stopWithStatus:message];
    });
}
- (void)markReceiving {
    if (_receiving.exchange(true)) return;
    const auto generation = _generation.load();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_active && generation == self->_generation.load()) {
            [self.delegate receiverStatus:@"Empfang läuft" active:YES];
            [self.delegate receiverPIN:@""];
        }
    });
}
- (void)receiveVideo:(video_decode_struct *)packet {
    if (!_active || packet->data_len <= 0 || (size_t)packet->data_len > receiver::maxAccessUnit) return;
    if (_videoPending.fetch_add(1) >= 4) { --_videoPending; return; }
    NSData *data = [NSData dataWithBytes:packet->data length:packet->data_len];
    const auto generation = _generation.load(), media = _videoGeneration.load();
    const auto time = presentation(packet->ntp_time_local);
    const BOOL hevc = packet->is_h265;
    if (_videoLogCount.load() < 6) {
        _videoLogCount++;
        struct timespec nowTs; clock_gettime(CLOCK_REALTIME, &nowTs);
        const int64_t wallNs = int64_t(nowTs.tv_sec) * 1000000000LL + nowTs.tv_nsec;
        const long long deltaMs = ((long long)packet->ntp_time_local - (long long)wallNs) / 1000000LL;
        [self postDiagnostic:[NSString stringWithFormat:@"Videopaket: %d Bytes, %@, Zeitabweichung %lld ms, %@",
            (int)packet->data_len, hevc ? @"H.265" : @"H.264", deltaMs, time ? @"eingeplant" : @"VERWORFEN"]];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_active && generation == self->_generation.load() && media == self->_videoGeneration.load() && time) {
            if ([self->_video enqueueAnnexB:data hevc:hevc presentationTime:*time]) [self markReceiving];
            else if (self->_videoLogCount.load() < 12) {
                self->_videoLogCount++;
                [self postDiagnostic:@"Video: Wiedergabe fehlgeschlagen (noch kein SPS/PPS, Layer ausgelastet oder Decoderfehler)"];
            }
        }
        --self->_videoPending;
    });
}
- (void)configureAudio:(uint8_t)compression frames:(uint32_t)frames {
    const auto generation = _generation.load();
    const auto media = ++_audioGeneration;
    dispatch_async(_audioQueue, ^{
        if (!self->_active || generation != self->_generation.load() || media != self->_audioGeneration.load()) return;
        NSError *error = nil;
        if (![self->_audio configureCompression:compression framesPerPacket:frames error:&error])
            [self postDiagnostic:[NSString stringWithFormat:@"Audio-Initialisierungsfehler: %@", error.localizedDescription]];
        else
            [self postDiagnostic:[NSString stringWithFormat:@"Audio bereit: Codec %u, %u Frames pro Paket", compression, frames]];
    });
}
- (void)receiveAudio:(audio_decode_struct *)packet {
    if (!_active || packet->data_len <= 0 || packet->data_len > 65536) return;
    if (_audioPending.fetch_add(1) >= 96) { --_audioPending; return; }
    NSData *data = [NSData dataWithBytes:packet->data length:packet->data_len];
    const auto generation = _generation.load(), media = _audioGeneration.load();
    const auto time = presentation(packet->ntp_time_local);
    dispatch_async(_audioQueue, ^{
        if (self->_active && generation == self->_generation.load() && media == self->_audioGeneration.load() && time)
            if ([self->_audio enqueuePacket:data presentationTime:*time]) [self markReceiving];
            else if (self->_audioLogCount.load() < 4) {
                self->_audioLogCount++;
                [self postDiagnostic:[NSString stringWithFormat:@"Audiopaket abgelehnt: %@", self->_audio.lastFailure ?: @"unbekannt"]];
            }
        --self->_audioPending;
    });
}
- (void)flushVideo {
    const auto media = ++_videoGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{ if (media == self->_videoGeneration.load()) [self->_video flush]; });
}
- (void)flushAudio {
    const auto media = ++_audioGeneration;
    dispatch_async(_audioQueue, ^{ if (media == self->_audioGeneration.load()) [self->_audio flush]; });
}
- (void)endStream {
    resetPresentationAnchor();
    [self flushAudio]; [self flushVideo]; _receiving = false;
    const auto generation = _generation.load();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_active && generation == self->_generation.load()) [self.delegate receiverStatus:@"Wartet auf Verbindung" active:YES];
    });
}
- (void)stop {
    [self stopWithStatus:@"Gestoppt"];
}
- (void)stopWithStatus:(NSString *)status {
    NSAssert(NSThread.isMainThread, @"Control from main queue");
    if (_stopping) return;
    _stopping = YES;
    _active = false; ++_generation; _receiving = false;
    [self flushVideo]; [self flushAudio];
    [self.delegate receiverPIN:@""];
    [self.delegate receiverStatus:@"Wird beendet…" active:YES];
    dispatch_async(_controlQueue, ^{
        if (self->_dnssd) { dnssd_unregister_raop(self->_dnssd); dnssd_unregister_airplay(self->_dnssd); }
        if (self->_raop) { raop_destroy(self->_raop); self->_raop = nullptr; }
        if (self->_dnssd) { dnssd_destroy(self->_dnssd); self->_dnssd = nullptr; }
        dispatch_sync(self->_audioQueue, ^{ [self->_audio stop]; });
        [AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_stopping = NO;
            [self.delegate receiverStatus:status active:NO];
        });
    });
}
- (void)probeAirPlay2Ports {
    dispatch_async(_controlQueue, ^{
        const auto result = receiver::probePTPPorts();
        NSString *message = result.available
            ? @"PTP-Diagnose: UDP 319/320 exklusiv gebunden. PTP-Empfang, Zeitsynchronisierung und AirPlay-2-Wiedergabe sind ungetestet."
            : [NSString stringWithFormat:@"PTP-Diagnose: UDP %u nicht verfügbar: %s (%d)", result.failedPort, strerror(result.error), result.error];
        [self postDiagnostic:message];
    });
}
@end
