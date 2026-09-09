APP_NAME := Inkling
CONFIGURATION ?= debug
BUILD_DIR := .build/$(CONFIGURATION)
APP_BUNDLE := build/$(APP_NAME).app

.PHONY: build test app run check

build:
	swift build -c $(CONFIGURATION)

test:
	swift test

app: build
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --sign - "$(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

check: test app
