ifeq ($(THEOS),)
$(error THEOS is not set. export THEOS=~/theos)
endif

# iOS 16.5 SDK (from theos/sdks); tested on iOS 16.1.1.
TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockScreenRestore

LockScreenRestore_FILES = Tweak.xm DebugTools.m
LockScreenRestore_CFLAGS = -fobjc-arc
LockScreenRestore_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += lockscreenrestoreprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
