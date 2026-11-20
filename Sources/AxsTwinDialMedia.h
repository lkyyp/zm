#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(unsigned int, AxsTwinDialCommand) {
    AxsTwinDialCommandToggle = 2,
    AxsTwinDialCommandNext = 4,
    AxsTwinDialCommandPrevious = 5
};
void axs_twindial_nowPlaying(void (^reply)(NSDictionary *info, BOOL playing));
BOOL axs_twindial_sendCommand(AxsTwinDialCommand command);
BOOL axs_twindial_getVolume(float *volume);
BOOL axs_twindial_setVolume(float volume);
