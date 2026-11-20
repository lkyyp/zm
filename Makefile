DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsTwinDialBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsTwinDial
AxsTwinDial_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsTwinDial_CFLAGS = -fobjc-arc -I./Headers -I./Sources
AxsTwinDial_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore CoreGraphics
AxsTwinDial_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsTwinDialPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
