TARGET := iphone:clang:latest:11.0
INSTALL_TARGET_PROCESSES = YouTube
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTweaks

$(TWEAK_NAME)_FILES = Settings.x Tweak.x
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

ifeq ($(ROOTLESS),1)
after-stage::
	@find $(THEOS_STAGING_DIR) -type f | while read f; do \
		if file "$$f" | grep -q "Mach-O"; then \
			if otool -L "$$f" | grep -q "/Library/Frameworks/CydiaSubstrate.framework"; then \
				install_name_tool -change \
					/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
					@rpath/CydiaSubstrate.framework/CydiaSubstrate \
					"$$f"; \
			fi; \
		fi; \
	done
endif