#import <AVFoundation/AVFoundation.h>
NS_ASSUME_NONNULL_BEGIN
@protocol ReceiverEngineDelegate <NSObject>
- (void)receiverStatus:(NSString *)status active:(BOOL)active;
- (void)receiverPIN:(NSString *)pin;
- (void)receiverDiagnostic:(NSString *)message;
@end

@interface ReceiverEngine : NSObject
@property(nonatomic, weak, nullable) id<ReceiverEngineDelegate> delegate;
@property(nonatomic, readonly) AVSampleBufferDisplayLayer *displayLayer;
- (void)startWithName:(NSString *)name identity:(NSData *)identity storageURL:(NSURL *)storage requirePIN:(BOOL)requirePIN;
- (void)stop;
- (void)probeAirPlay2Ports;
@end
NS_ASSUME_NONNULL_END
