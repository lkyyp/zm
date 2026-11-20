#import "AxsTwinDialMedia.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <math.h>

static void (*AxsTwinDialInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
static Boolean (*AxsTwinDialSend)(AxsTwinDialCommand, CFDictionaryRef);

static void axs_twindial_loadMedia(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) return;
        AxsTwinDialInfo = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        AxsTwinDialSend = dlsym(handle, "MRMediaRemoteSendCommand");
    });
}

void axs_twindial_nowPlaying(void (^reply)(NSDictionary *, BOOL)) {
    axs_twindial_loadMedia();
    if (!AxsTwinDialInfo) { reply(@{}, NO); return; }
    AxsTwinDialInfo(dispatch_get_main_queue(), ^(CFDictionaryRef value) {
        NSDictionary *info = (__bridge NSDictionary *)value ?: @{};
        id rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        reply(info, [rate isKindOfClass:NSNumber.class] && [rate doubleValue] > 0);
    });
}

BOOL axs_twindial_sendCommand(AxsTwinDialCommand command) {
    axs_twindial_loadMedia();
    return AxsTwinDialSend && AxsTwinDialSend(command, NULL);
}

@protocol AxsTwinDialSystemVolume <NSObject>
+ (id<AxsTwinDialSystemVolume>)sharedAVSystemController;
- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
- (BOOL)setVolumeTo:(float)volume forCategory:(NSString *)category;
@end

static id<AxsTwinDialSystemVolume> axs_twindial_volumeController(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!NSClassFromString(@"AVSystemController"))
            dlopen("/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience", RTLD_LAZY | RTLD_LOCAL);
    });
    Class<AxsTwinDialSystemVolume> cls = (Class<AxsTwinDialSystemVolume>)NSClassFromString(@"AVSystemController");
    if (![cls respondsToSelector:@selector(sharedAVSystemController)]) return nil;
    id<AxsTwinDialSystemVolume> controller = [cls sharedAVSystemController];
    if (![controller respondsToSelector:@selector(getVolume:forCategory:)] ||
        ![controller respondsToSelector:@selector(setVolumeTo:forCategory:)]) return nil;
    const char *readArg = @encode(float *), *writeArg = @encode(float);
    NSMethodSignature *r = [(NSObject *)controller methodSignatureForSelector:@selector(getVolume:forCategory:)];
    NSMethodSignature *w = [(NSObject *)controller methodSignatureForSelector:@selector(setVolumeTo:forCategory:)];
    if (r.numberOfArguments != 4 || w.numberOfArguments != 4 ||
        strcmp(r.methodReturnType, @encode(BOOL)) || strcmp(w.methodReturnType, @encode(BOOL)) ||
        strcmp([r getArgumentTypeAtIndex:2], readArg) || strcmp([w getArgumentTypeAtIndex:2], writeArg) ||
        strcmp([r getArgumentTypeAtIndex:3], "@") || strcmp([w getArgumentTypeAtIndex:3], "@")) return nil;
    return controller;
}

BOOL axs_twindial_getVolume(float *volume) {
    return volume && [axs_twindial_volumeController() getVolume:volume forCategory:@"Audio/Video"] && isfinite(*volume);
}

BOOL axs_twindial_setVolume(float volume) {
    return isfinite(volume) && [axs_twindial_volumeController() setVolumeTo:fmaxf(0, fminf(1, volume)) forCategory:@"Audio/Video"];
}
