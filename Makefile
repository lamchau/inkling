APP_NAME := Inkling
CONFIGURATION ?= debug
BUILD_DIR := .build/$(CONFIGURATION)
APP_BUNDLE := build/$(APP_NAME).app
RESOURCE_BUNDLE := $(BUILD_DIR)/$(APP_NAME)_$(APP_NAME).bundle

.PHONY: build test app run check

build:
	swift build -c $(CONFIGURATION)

test:
	swift test

app: build
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp -R "$(RESOURCE_BUNDLE)" "$(APP_BUNDLE)/Contents/Resources/"
	codesign --force --sign - "$(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

check: test app
