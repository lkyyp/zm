include ../AxsTwinDialBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AxsTwinDialPrefs
AxsTwinDialPrefs_FILES = $(wildcard *.m)
AxsTwinDialPrefs_CFLAGS = -fobjc-arc -I../Sources
AxsTwinDialPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation PhotosUI ImageIO UniformTypeIdentifiers CoreGraphics
AxsTwinDialPrefs_PRIVATE_FRAMEWORKS = Preferences
AxsTwinDialPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
