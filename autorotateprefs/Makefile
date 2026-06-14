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

include $(THEOS_MAKE_PATH)/bundle.mk
