export ARCHS = arm64
export TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Omega

Omega_FILES = $(wildcard Sources/*.m)
Omega_FRAMEWORKS = UIKit
Omega_CFLAGS = -fobjc-arc
Omega_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS)/makefiles/application.mk
