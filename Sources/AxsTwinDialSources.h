#import <Foundation/Foundation.h>
NSURLSessionDataTask *axs_twindial_lookupLyrics(NSArray *track, void (^reply)(NSString *text, NSString *status, BOOL retry));
NSDictionary<NSString *,NSString *> *axs_twindial_systemWeather(void);
