#import <Foundation/Foundation.h>
#include "dnssd.h"
// Configure before registrations. Handler is called on the main queue.
void ReceiverBonjourSetHandler(dnssd_t *service, void (^handler)(NSString *type, NSError *error));
