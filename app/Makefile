export ARCHS = arm64
export TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Omega

Omega_FILES = $(wildcard Sources/*.m)
Omega_FRAMEWORKS = UIKit WebKit
Omega_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/application.mk
