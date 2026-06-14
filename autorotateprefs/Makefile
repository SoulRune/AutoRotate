# Subprojects run their own make pass and don't inherit the top Makefile, so the
# arch/target/linker settings are repeated here (see ../Makefile for the why).
ARCHS = arm64
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = autorotateprefs

autorotateprefs_FILES = ARStore.m ARListBase.m ARRootListController.m ARAppListController.m ARAppsTableController.m ARBulkOrientationController.m
autorotateprefs_INSTALL_PATH = /Library/PreferenceBundles
autorotateprefs_FRAMEWORKS = UIKit
autorotateprefs_PRIVATE_FRAMEWORKS = Preferences
autorotateprefs_CFLAGS = -fobjc-arc
autorotateprefs_LDFLAGS = -Wl,-platform_version,ios,15.0,16.5

# Mirror the tweak's AR_DEBUG flag so the "Debug logging" switch is only built in debug
# packages (the command-line variable propagates to this subproject's make).
ifeq ($(AR_DEBUG),1)
autorotateprefs_CFLAGS += -DAR_DEBUG=1
endif

include $(THEOS_MAKE_PATH)/bundle.mk
