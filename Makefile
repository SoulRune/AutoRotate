export THEOS_PACKAGE_SCHEME = rootless   # default; for a rootful .deb: make package THEOS_PACKAGE_SCHEME=

# arm64 only: the Linux Swift toolchain's clang doesn't tag arm64e with a distinct
# CPU subtype, so lipo can't merge the two slices. arm64 is enough for App Store /
# user apps (which run as arm64); add arm64e back on a macOS toolchain.
ARCHS = arm64
# platform:compiler:sdk:deployment. iOS 15.0 minimum (rootless-era tweak). A modern
# minimum also makes clang emit the -platform_version flag ld64.lld needs. "latest"
# picks the newest installed SDK.
TARGET = iphone:clang:latest:15.0
DEBUG = 0
FINALPACKAGE = 1
FOR_RELEASE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoRotate

AutoRotate_FILES = Tweak.xm
AutoRotate_CFLAGS = -fobjc-arc
AutoRotate_FRAMEWORKS = UIKit Foundation
AutoRotate_LDFLAGS = -Wl,-platform_version,ios,15.0,16.5

# Build the per-app Settings panel together with the tweak.
SUBPROJECTS = autorotateprefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
