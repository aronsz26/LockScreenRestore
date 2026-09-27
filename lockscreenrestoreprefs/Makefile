TARGET := iphone:clang:16.5:14.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LockScreenRestorePrefs

LockScreenRestorePrefs_FILES = LSRRootListController.m
LockScreenRestorePrefs_FRAMEWORKS = UIKit
LockScreenRestorePrefs_PRIVATE_FRAMEWORKS = Preferences FrontBoardServices SpringBoardServices
LockScreenRestorePrefs_INSTALL_PATH = /Library/PreferenceBundles
LockScreenRestorePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/LockScreenRestorePrefs.plist$(ECHO_END)
