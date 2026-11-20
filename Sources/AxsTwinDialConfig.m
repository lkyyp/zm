#import "AxsTwinDialConfig.h"
#import "AxsTwinDialPreferences.h"

@interface AxsTwinDialConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void axs_twindial_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    AxsTwinDialConfig *config = (__bridge AxsTwinDialConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config axs_twindial_reload];
    });
}

@implementation AxsTwinDialConfig

+ (instancetype)axs_twindial_shared {
    static AxsTwinDialConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.axs.twindial.preferences", DISPATCH_QUEUE_SERIAL);
        [self axs_twindial_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, axs_twindial_preferencesDidChange,
            (__bridge CFStringRef)AxsTwinDialPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self axs_twindial_reload]; });
    }
    return self;
}

- (void)axs_twindial_reload {
    self.snapshot = axs_twindial_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AxsTwinDialPreferencesChanged object:self];
    });
}

- (id)axs_twindial_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)axs_twindial_isEnabled {
    id value = [self axs_twindial_valueForKey:@"enabled" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
