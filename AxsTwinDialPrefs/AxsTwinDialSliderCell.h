#pragma once

#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
#include <math.h>

@protocol AxsTwinDialSliderCellHandler <NSObject>
- (double)axs_twindial_sliderValueForSpecifier:(PSSpecifier *)specifier;
- (void)axs_twindial_setSliderValue:(double)value specifier:(PSSpecifier *)specifier;
@end

@interface AxsTwinDialSliderCell : PSTableCell
@property (nonatomic, weak) id<AxsTwinDialSliderCellHandler> handler;
- (void)axs_twindial_reloadState;
@end
