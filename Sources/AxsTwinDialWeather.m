#import "AxsTwinDialWeather.h"
#import <math.h>

static NSDictionary *axs_twindial_dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }
static NSString *axs_twindial_text(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }
static BOOL axs_twindial_weatherNumber(id v, double lo, double hi, double *out) {
    if (![v isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) return NO;
    double n = [v doubleValue];
    if (!isfinite(n) || n < lo || n > hi) return NO;
    *out = n; return YES;
}

static void axs_twindial_weatherJSON(NSString *host, NSString *path, NSDictionary *query, void (^done)(NSDictionary *)) {
    NSURLComponents *url = [NSURLComponents new];
    url.scheme = @"https"; url.host = host; url.path = path;
    NSMutableArray *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:key value:value]];
    }];
    url.queryItems = items;
    url.percentEncodedQuery = [url.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
    NSURL *target = url.URL;
    if (!target) { done(nil); return; }
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 7; config.timeoutIntervalForResource = 9;
    config.HTTPCookieStorage = nil; config.URLCredentialStorage = nil; config.URLCache = nil;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    [[session dataTaskWithURL:target completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || ![response isKindOfClass:NSHTTPURLResponse.class] ||
            [(NSHTTPURLResponse *)response statusCode] != 200 || ![response.URL.host isEqualToString:host] ||
            data.length == 0 || data.length > 65536) { done(nil); return; }
        done(axs_twindial_dict([NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]));
    }] resume];
    [session finishTasksAndInvalidate];
}

static NSString *axs_twindial_condition(NSInteger code) {
    if (code == 0) return @"晴";
    if (code >= 1 && code <= 2) return @"多云";
    if (code == 3) return @"阴";
    if (code == 45 || code == 48) return @"雾";
    if (code >= 95) return @"雷暴";
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return @"雪";
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return @"雨";
    return @"暂无描述";
}

static id axs_twindial_onlyDailyValue(id value) {
    if (![value isKindOfClass:NSArray.class]) return nil;
    NSArray *values = value;
    return values.count == 1 ? values.firstObject : nil;
}

static void axs_twindial_forecast(NSString *name, double lat, double lon, AxsTwinDialWeatherReply finish) {
    NSDictionary *params = @{@"latitude": @(lat).stringValue, @"longitude": @(lon).stringValue,
        @"current": @"weather_code",
        @"daily": @"temperature_2m_min,temperature_2m_max,precipitation_probability_max",
        @"temperature_unit": @"celsius", @"timezone": @"auto", @"forecast_days": @"1"};
    axs_twindial_weatherJSON(@"api.open-meteo.com", @"/v1/forecast", params, ^(NSDictionary *json) {
        NSDictionary *current = axs_twindial_dict(json[@"current"]);
        NSDictionary *daily = axs_twindial_dict(json[@"daily"]);
        NSString *currentTime = axs_twindial_text(current[@"time"]);
        NSString *localDate = axs_twindial_text(axs_twindial_onlyDailyValue(daily[@"time"]));
        double low, high, rain, code = -1;
        // Both timestamps use the forecast location's timezone, not the device timezone.
        if (localDate.length != 10 || ![currentTime hasPrefix:[localDate stringByAppendingString:@"T"]] ||
            !axs_twindial_weatherNumber(axs_twindial_onlyDailyValue(daily[@"temperature_2m_min"]), -150, 150, &low) ||
            !axs_twindial_weatherNumber(axs_twindial_onlyDailyValue(daily[@"temperature_2m_max"]), -150, 150, &high) ||
            low > high ||
            !axs_twindial_weatherNumber(axs_twindial_onlyDailyValue(daily[@"precipitation_probability_max"]), 0, 100, &rain)) {
            finish(nil, @"天气暂不可用"); return;
        }
        axs_twindial_weatherNumber(current[@"weather_code"], 0, 99, &code);
        // No authoritative warning feed is integrated; an absent alert is not an all-clear.
        finish(@{@"condition": axs_twindial_condition((NSInteger)code),
                 @"range": [NSString stringWithFormat:@"%ld–%ld °C", lround(low), lround(high)],
                 @"location": name,
                 @"rain": [NSString stringWithFormat:@"降水 %.0f%%", rain]}, nil);
    });
}

static BOOL axs_twindial_coord(NSString *input, double limit, double *out) {
    NSScanner *scan = [NSScanner scannerWithString:input];
    double value;
    if (![scan scanDouble:&value] || !scan.isAtEnd || !isfinite(value) || fabs(value)>limit) return NO;
    *out = value; return YES;
}

void axs_twindial_fetchWeather(NSString *city, AxsTwinDialWeatherReply reply) {
    AxsTwinDialWeatherReply finish = ^(NSDictionary *data, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ reply(data,error); });
    };
    if (!city.length || city.length > 160 || ![city canBeConvertedToEncoding:NSUTF8StringEncoding] || [city rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        finish(nil,@"城市无效"); return;
    }
    NSArray *named = [city componentsSeparatedByString:@"@"]; NSString *name = city;
    NSString *tail = [named.lastObject stringByReplacingOccurrencesOfString:@"，" withString:@","];
    NSArray<NSString *> *pair = [tail componentsSeparatedByString:@","];
    double lat, lon;
    if (named.count <= 2 && pair.count == 2 && axs_twindial_coord(pair[0],90,&lat) && axs_twindial_coord(pair[1],180,&lon)) {
        name = (named.count == 2 && [named.firstObject length]) ? named.firstObject : @"自定义地点";
        axs_twindial_forecast(name,lat,lon,finish); return;
    }
    if (named.count != 1) { finish(nil,@"坐标格式不正确"); return; }
    if (name.length > 2 && [name hasSuffix:@"市"]) name = [name substringToIndex:name.length-1];
    axs_twindial_weatherJSON(@"geocoding-api.open-meteo.com", @"/v1/search", @{@"name":name,@"count":@"5",@"language":@"zh"}, ^(NSDictionary *json) {
        if (!json) { finish(nil,@"天气服务暂不可用"); return; }
        id results = json[@"results"];
        if ([results isKindOfClass:NSArray.class]) for (id found in results) {
            NSDictionary *place = axs_twindial_dict(found);
            NSString *label = axs_twindial_text(place[@"name"]);
            double x,y;
            if (label.length && axs_twindial_weatherNumber(place[@"latitude"],-90,90,&x) && axs_twindial_weatherNumber(place[@"longitude"],-180,180,&y)) {
                axs_twindial_forecast(label,x,y,finish); return;
            }
        }
        finish(nil,@"找不到该城市");
    });
}
