#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef void (^AxsTwinDialWeatherReply)(NSDictionary<NSString *,NSString *> * _Nullable data, NSString * _Nullable error);
void axs_twindial_fetchWeather(NSString *city, AxsTwinDialWeatherReply reply);
NS_ASSUME_NONNULL_END
