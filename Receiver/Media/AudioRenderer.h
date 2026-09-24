#import <AVFoundation/AVFoundation.h>
NS_ASSUME_NONNULL_BEGIN
// Caller serializes all methods on its audio queue. Completions are internal.
@interface AudioRenderer : NSObject
- (BOOL)configureCompression:(uint8_t)compression framesPerPacket:(uint32_t)frames error:(NSError **)error;
- (BOOL)enqueuePacket:(NSData *)data presentationTime:(uint64_t)hostNanoseconds;
- (void)setVolumeDecibels:(float)volume;
- (void)flush;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
