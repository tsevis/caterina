# FlickrDownloader
#
# `make test` is offline and headless and opens no window. Keep it that way.

SPEC      := App/project.yml
PROJECT   := App/FlickrDownloader.xcodeproj
SCHEME    := FlickrDownloader
DERIVED   := .build/xcode
APP       := $(DERIVED)/Build/Products/Release/FlickrDownloader.app
SIGN      := ../sign-and-notarize.sh

.PHONY: all build test coverage lint project app run sign clean

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
sign: app
	$(SIGN) $(APP)

clean:
	rm -rf .build $(PROJECT)
