// TXT fields follow UxPlay's lib/dns_sd/dns_sd.c (LGPL-2.1-or-later).
// Copyright 2011-2012 Juho Vähä-Herttua; modifications fduncanh 2022, 2026.
#import "Bonjour.h"
#include "dnssdint.h"

@interface ReceiverServiceDelegate : NSObject <NSNetServiceDelegate>
@property(nonatomic, copy) void (^handler)(NSString *, NSError *);
@end
@implementation ReceiverServiceDelegate
- (void)netServiceDidPublish:(NSNetService *)sender {
    if (_handler) _handler(sender.type, nil);
}
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *, NSNumber *> *)errorDict {
    NSError *error = [NSError errorWithDomain:@"ReceiverBonjour" code:[errorDict[NSNetServicesErrorCode] integerValue]
        userInfo:@{NSLocalizedDescriptionKey:@"Empfänger kann nicht veröffentlicht werden. Bitte in den Einstellungen den Zugriff auf das lokale Netzwerk und die WLAN-Verbindung prüfen."}];
    if (_handler) _handler(sender.type, error);
}
@end

struct BonjourState {
    NSNetService *raop = nil, *airplay = nil;
    NSData *raopTXT = nil, *airplayTXT = nil;
    ReceiverServiceDelegate *delegate = [ReceiverServiceDelegate new];
};
static void onMain(dispatch_block_t action) {
    if (NSThread.isMainThread) action(); else dispatch_sync(dispatch_get_main_queue(), action);
}
static NSData *txt(NSDictionary<NSString *, NSString *> *fields) {
    NSMutableDictionary *encoded = [NSMutableDictionary dictionary];
    for (NSString *key in fields) encoded[key] = [fields[key] dataUsingEncoding:NSUTF8StringEncoding];
    return [NSNetService dataFromTXTRecordDictionary:encoded];
}
static NSString *deviceID(dnssd_t *service, NSString *separator) {
    NSMutableArray *bytes = [NSMutableArray array];
    for (int i = 0; i < service->hw_addr_len; ++i)
        [bytes addObject:[NSString stringWithFormat:@"%02X", (unsigned char)service->hw_addr[i]]];
    return [bytes componentsJoinedByString:separator];
}
static NSString *features(dnssd_t *service) {
    return [NSString stringWithFormat:@"0x%X,0x%X", service->features1, service->features2];
}
void ReceiverBonjourSetHandler(dnssd_t *service, void (^handler)(NSString *, NSError *)) {
    auto *state = static_cast<BonjourState *>(service->dnssd_private);
    onMain(^{ state->delegate.handler = handler; });
}
extern "C" {
void *dnssd_private_init(dnssd_t *, int *error) {
    if (error) *error = 0;
    return new BonjourState;
}
void dnssd_private_destroy(void *pointer) {
    auto *state = static_cast<BonjourState *>(pointer);
    onMain(^{
        state->delegate.handler = nil;
        state->raop.delegate = nil; state->airplay.delegate = nil;
        [state->raop stop]; [state->airplay stop];
    });
    delete state;
}
int dnssd_register_raop(dnssd_t *service, unsigned short port) {
    auto *state = static_cast<BonjourState *>(service->dnssd_private);
    NSString *name = [NSString stringWithFormat:@"%@@%s", deviceID(service, @""), service->name];
    state->raopTXT = txt(@{@"ch":@RAOP_CH, @"cn":@"1,2,3", @"da":@RAOP_DA, @"et":@RAOP_ET,
        @"vv":@RAOP_VV, @"ft":features(service), @"am":@GLOBAL_MODEL, @"md":@"",
        @"rhd":@RAOP_RHD, @"pw":service->pin_pw ? @"true" : @"false",
        @"sf":service->pin_pw ? @"0x8c" : @RAOP_SF, @"sr":@RAOP_SR, @"ss":@RAOP_SS,
        @"sv":@RAOP_SV, @"tp":@RAOP_TP, @"txtvers":@RAOP_TXTVERS, @"vs":@RAOP_VS,
        @"vn":@RAOP_VN, @"pk":[NSString stringWithUTF8String:service->pk]});
    onMain(^{
        state->raop = [[NSNetService alloc] initWithDomain:@"local." type:@"_raop._tcp." name:name port:port];
        state->raop.delegate = state->delegate;
        [state->raop setTXTRecordData:state->raopTXT];
        [state->raop publish];
    });
    return 0;
}
int dnssd_register_airplay(dnssd_t *service, unsigned short port) {
    auto *state = static_cast<BonjourState *>(service->dnssd_private);
    state->airplayTXT = txt(@{@"deviceid":deviceID(service, @":"), @"features":features(service),
        @"pw":service->pin_pw ? @"true" : @"false", @"flags":@"0x4", @"model":@GLOBAL_MODEL,
        @"pk":[NSString stringWithUTF8String:service->pk], @"pi":@AIRPLAY_PI,
        @"srcvers":@AIRPLAY_SRCVERS, @"vv":@AIRPLAY_VV});
    NSString *name = [NSString stringWithUTF8String:service->name];
    onMain(^{
        state->airplay = [[NSNetService alloc] initWithDomain:@"local." type:@"_airplay._tcp." name:name port:port];
        state->airplay.delegate = state->delegate;
        [state->airplay setTXTRecordData:state->airplayTXT];
        [state->airplay publish];
    });
    return 0;
}
void dnssd_unregister_raop(dnssd_t *service) {
    auto *state = static_cast<BonjourState *>(service->dnssd_private);
    onMain(^{ state->raop.delegate = nil; [state->raop stop]; state->raop = nil; });
}
void dnssd_unregister_airplay(dnssd_t *service) {
    auto *state = static_cast<BonjourState *>(service->dnssd_private);
    onMain(^{ state->airplay.delegate = nil; [state->airplay stop]; state->airplay = nil; });
}
const char *dnssd_get_raop_txt(dnssd_t *service, int *length) {
    auto *state = static_cast<BonjourState *>(service->dnssd_private);
    *length = (int)state->raopTXT.length;
    return (const char *)state->raopTXT.bytes;
}
const char *dnssd_get_airplay_txt(dnssd_t *service, int *length) {
    auto *state = static_cast<BonjourState *>(service->dnssd_private);
    *length = (int)state->airplayTXT.length;
    return (const char *)state->airplayTXT.bytes;
}
}
