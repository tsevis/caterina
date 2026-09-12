# FlickrDownloader
#
# `make test` is offline and headless and opens no window. Keep it that way.

SPEC      := App/project.yml
PROJECT   := App/FlickrDownloader.xcodeproj
SCHEME    := FlickrDownloader
DERIVED   := .build/xcode
APP       := $(DERIVED)/Build/Products/Release/FlickrDownloader.app
SIGN      := ../sign-and-notarize.sh
ENTS      := App/FlickrDownloader/FlickrDownloader.entitlements

.PHONY: all build test coverage lint project app run sign sign-only clean

all: lint test app

## Build the package (no Xcode needed).
build:
	swift build

## The whole suite. Offline, headless, no windows.
test: lint
	swift test

coverage:
	swift test --enable-code-coverage
	xcrun llvm-cov report \
		.build/debug/FlickrKitPackageTests.xctest/Contents/MacOS/FlickrKitPackageTests \
		-instr-profile=.build/debug/codecov/default.profdata \
		Sources/FlickrKit/*.swift

## FlickrKit must link no UI framework: that is what makes it testable
## headlessly, and a stray import is easier to add than to notice.
lint:
	@! grep -rlE '^import (SwiftUI|AppKit|UIKit)' Sources/FlickrKit \
		|| (echo "error: FlickrKit must not import a UI framework" && exit 1)
	@echo "  ok  FlickrKit links no UI framework"

project:
	xcodegen generate --spec $(SPEC)

## The signed-for-development app bundle.
app: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO build

run: app
	open $(APP)

## Developer ID signature, notarisation, stapled DMG. Not --python.
##
## `--entitlements` is not optional here: `codesign --force` without it
## re-signs with none at all, and this app is sandboxed. The script verifies
## they survived.
sign: app
	$(SIGN) --entitlements $(ENTS) $(APP)

## Everything `sign` does except talking to Apple.
sign-only: app
	$(SIGN) --entitlements $(ENTS) --sign-only $(APP)

clean:
	rm -rf .build $(PROJECT)
