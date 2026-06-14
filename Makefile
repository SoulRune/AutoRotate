export THEOS_PACKAGE_SCHEME = rootless   # default; for a rootful .deb: make package THEOS_PACKAGE_SCHEME=

# arm64 only by default: the Linux Swift toolchain's clang doesn't tag arm64e with a
# distinct CPU subtype, so lipo can't merge the two slices.
#
# IMPORTANT: arm64 alone hooks App Store / user apps everywhere, but on A12+ devices the
# system processes (SpringBoard, Preferences, stock apps) run as arm64e — an arm64-only
# dylib will NOT inject into them. To target system apps on A12+ you must add an arm64e
# slice, which needs a macOS toolchain:  make package ARCHS="arm64 arm64e"
# (A11 devices — iPhone 8/X, the iOS 16 floor — are arm64, so arm64-only is fine there.)
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

# Debug build: `make package AR_DEBUG=1` compiles in the file logger + "Debug logging"
# switch. Without it, that code (and the switch) is absent from the package. The "+debug"
# version suffix keeps the debug .deb from clobbering the release one.
ifeq ($(AR_DEBUG),1)
AutoRotate_CFLAGS += -DAR_DEBUG=1
# Override the version theos uses for both the .deb filename and the control, so the debug
# package can't clobber the release one. Read the base straight from control (robust no
# matter when theos sets its own version variable).
THEOS_PACKAGE_BASE_VERSION := $(shell grep '^Version:' control | awk '{print $$2}')+debug
endif

# Build the per-app Settings panel together with the tweak.
SUBPROJECTS = autorotateprefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
