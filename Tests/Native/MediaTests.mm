#import <XCTest/XCTest.h>
#import "VideoRenderer.h"
#import "AudioRenderer.h"
#include "Clock.hpp"

@interface MediaTests : XCTestCase
@end
@implementation MediaTests
- (void)testMalformedVideoDoesNotReachDisplayLayer {
    void (^test)(void) = ^{
        VideoRenderer *renderer = [VideoRenderer new];
        const uint8_t malformed[] = {0,0,0,1};
        XCTAssertFalse([renderer enqueueAnnexB:[NSData dataWithBytes:malformed length:sizeof(malformed)]
                                         hevc:NO presentationTime:1]);
        [renderer flush]; [renderer flush];
        XCTAssertNotNil(renderer.layer);
    };
    if (NSThread.isMainThread) test(); else dispatch_sync(dispatch_get_main_queue(), test);
}
- (void)testUnsupportedAudioFormatFailsWithoutStartingEngine {
    AudioRenderer *renderer = [AudioRenderer new];
    NSError *error = nil;
    XCTAssertFalse([renderer configureCompression:255 framesPerPacket:480 error:&error]);
    XCTAssertNotNil(error);
    XCTAssertFalse([renderer enqueuePacket:[NSData dataWithBytes:"abc" length:3] presentationTime:1]);
    [renderer stop]; [renderer stop];
}
- (void)testRealtimeClockDiscontinuityIsRejected {
    XCTAssertFalse(receiver::hostPresentationTime(10000000000ULL, 1, 500000, 0).has_value());
    auto target = receiver::hostPresentationTime(1000000000, 900000000, 2000000000, 0);
    XCTAssertTrue(target.has_value());
    XCTAssertEqual(*target, 2100000000ULL);
}
@end
