#import "AxsTwinDialSources.h"
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>

NSURLSessionDataTask *axs_twindial_lookupLyrics(NSArray *track, void (^reply)(NSString *, NSString *, BOOL)) {
    NSURLComponents *url = [NSURLComponents componentsWithString:@"https://lrclib.net/api/get"];
    NSMutableArray *q = [NSMutableArray array];
    NSArray *keys = @[@"track_name",@"artist_name",@"album_name",@"duration"];
    for (NSUInteger i=0; i<keys.count; ++i) [q addObject:[NSURLQueryItem queryItemWithName:keys[i] value:[track[i] description]]];
    url.queryItems = q;
    url.percentEncodedQuery = [url.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
    if (!url.URL) return nil;
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 12;
        config.URLCache = nil; config.HTTPCookieStorage = nil; config.URLCredentialStorage = nil;
        session = [NSURLSession sessionWithConfiguration:config];
    });
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL];
    [request setValue:@"TwinDial/5.2 (optional synced lyrics)" forHTTPHeaderField:@"User-Agent"];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *text = nil, *status = @"无匹配歌词";
        BOOL retry = NO;
        NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (error || (code != 200 && code != 404) || ![response.URL.host isEqualToString:@"lrclib.net"] || ![response.URL.scheme isEqualToString:@"https"]) {
            status = @"歌词服务暂不可用"; retry = YES;
        } else if (code == 200 && data.length && data.length <= 524288) {
            id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            NSDictionary *entry = [decoded isKindOfClass:NSDictionary.class] ? decoded : nil;
            id duration = entry[@"duration"];
            if (entry && [duration isKindOfClass:NSNumber.class] && fabs([duration doubleValue]-[track[3] doubleValue]) <= 1.0) {
                BOOL match = YES;
                NSArray *fields = @[@"trackName",@"artistName",@"albumName"];
                for (NSUInteger i=0; i<fields.count; ++i) {
                    id value = entry[fields[i]];
                    if (![value isKindOfClass:NSString.class] || [track[i] caseInsensitiveCompare:[value precomposedStringWithCanonicalMapping]] != NSOrderedSame) match = NO;
                }
                id lyrics = entry[@"syncedLyrics"], instrumental = entry[@"instrumental"];
                if (match && [instrumental isEqual:@YES]) status = @"纯音乐";
                else if (match && [lyrics isKindOfClass:NSString.class] && [lyrics length] <= 65536 && [lyrics length]) text = lyrics;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ reply(text,status,retry); });
    }];
    [task resume];
    return task;
}

// Accept getters only. In particular, do not invoke any location activation or refresh APIs.
static id axs_twindial_weatherValue(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (![object respondsToSelector:sel]) return nil;
    NSMethodSignature *sig = [object methodSignatureForSelector:sel];
    if (sig.numberOfArguments != 2 || !sig.methodReturnType) return nil;
    if (sig.methodReturnType[0] == '@') return ((id (*)(id,SEL))objc_msgSend)(object,sel);
    switch (sig.methodReturnType[0]) {
        case 'B': return @(((BOOL (*)(id,SEL))objc_msgSend)(object,sel));
        case 'q': return @(((long long (*)(id,SEL))objc_msgSend)(object,sel));
        case 'Q': return @(((unsigned long long (*)(id,SEL))objc_msgSend)(object,sel));
        case 'i': return @(((int (*)(id,SEL))objc_msgSend)(object,sel));
        case 'I': return @(((unsigned int (*)(id,SEL))objc_msgSend)(object,sel));
        case 'd': return @(((double (*)(id,SEL))objc_msgSend)(object,sel));
        case 'f': return @(((float (*)(id,SEL))objc_msgSend)(object,sel));
        default: return nil;
    }
}
static NSString *axs_twindial_conditionText(NSInteger code) {
    if (code==32 || code==31 || code==33 || code==34 || code==36) return @"晴";
    if (code==26) return @"阴";
    if (code>=27 && code<=30) return @"多云";
    if ((code>=5 && code<=12) || code==35 || code==40) return @"雨";
    if (code==3 || code==4 || code==37 || code==38 || code==39 || code==45 || code==47) return @"雷雨";
    if ((code>=13 && code<=16) || code==41 || code==42 || code==43 || code==46) return @"雪";
    if (code==20) return @"雾";
    return nil;
}
NSDictionary<NSString *,NSString *> *axs_twindial_systemWeather(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dlopen("/System/Library/PrivateFrameworks/Weather.framework/Weather", RTLD_LAZY|RTLD_LOCAL); });
    id prefs = axs_twindial_weatherValue(NSClassFromString(@"WeatherPreferences"),@"sharedPreferences");
    id city = axs_twindial_weatherValue(prefs,@"localWeatherCity");
    id local = axs_twindial_weatherValue(city,@"isLocalWeatherCity");
    id date = axs_twindial_weatherValue(city,@"updateTime");
    if (![local isEqual:@YES] || ![date isKindOfClass:NSDate.class]) return nil;
    NSTimeInterval age = -[date timeIntervalSinceNow];
    if (!isfinite(age) || age < -120 || age > 3600) return nil;
    id name = axs_twindial_weatherValue(city,@"name");
    if (![name isKindOfClass:NSString.class] || ![name length]) return nil;
    NSMutableDictionary *result = [@{@"location":name} mutableCopy];
    id code = axs_twindial_weatherValue(city,@"conditionCode");
    NSString *condition = [code isKindOfClass:NSNumber.class] ? axs_twindial_conditionText([code integerValue]) : nil;
    id temp = axs_twindial_weatherValue(axs_twindial_weatherValue(city,@"temperature"),@"celsius");
    if ([temp isKindOfClass:NSNumber.class] && isfinite([temp doubleValue]) && fabs([temp doubleValue]) <= 100)
        result[@"condition"] = [NSString stringWithFormat:@"%@%@%.0f℃",condition ?: @"",condition ? @" · " : @"",[temp doubleValue]];
    else if (condition) result[@"condition"] = condition;
    return [result copy];
}
