#pragma once

#import <Foundation/Foundation.h>

@interface AxsTwinDialConfig : NSObject
+ (instancetype)axs_twindial_shared;
- (BOOL)axs_twindial_isEnabled;
- (id)axs_twindial_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)axs_twindial_reload;
@end
