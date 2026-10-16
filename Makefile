TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

# Default to rootless for Dopamine (iOS 15+)
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WhatsAppPlus

WhatsAppPlus_FILES = \
    src/Tweak.x \
    src/Settings/WATweakSettings.m \
    src/Settings/WATweakSettingsViewController.m \
    src/Translation/WATranslationManager.m \
    src/Translation/WAFloatingTranslateButton.m \
    src/Translation/WAChatInfoResolver.m \
    src/IconPicker/WAIconPickerViewController.m

WhatsAppPlus_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-nullability -Wno-error -Isrc
WhatsAppPlus_FRAMEWORKS = UIKit Foundation Security AudioToolbox NaturalLanguage

include $(THEOS_MAKE_PATH)/tweak.mk

after-all::
	@echo "[*] WhatsAppPlus build complete."
