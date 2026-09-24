#import <AVFoundation/AVFoundation.h>
NS_ASSUME_NONNULL_BEGIN
// All calls, including layer access, occur on the main queue.
@interface VideoRenderer : NSObject
@property(nonatomic, readonly) AVSampleBufferDisplayLayer *layer;
- (BOOL)enqueueAnnexB:(NSData *)data hevc:(BOOL)hevc presentationTime:(uint64_t)hostNanoseconds;
- (void)flush;
@end
NS_ASSUME_NONNULL_END
