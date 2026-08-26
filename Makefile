# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/Sotto-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build

# Local-build signing identity. Defaults to a self-signed root cert named
# "sotto-local" in the login keychain so each rebuild keeps a stable
# cdhash → macOS Accessibility / Input Monitoring permissions persist across
# rebuilds. Falls back to ad-hoc signing if the cert is not present.
#
# To create the cert (one-time, ~30 sec):
#   Keychain Access → Certificate Assistant → Create a Certificate…
#     Name: sotto-local
#     Identity Type: Self Signed Root
#     Certificate Type: Code Signing
#
# Override with: make local LOCAL_SIGN_IDENTITY="other-name" — exact name or SHA1.
LOCAL_SIGN_IDENTITY ?= $(shell /usr/bin/security find-identity -p codesigning -v 2>/dev/null | grep -F -e '"sotto-local"' -e '"voiceink-fork-local"' | head -1 | awk '{ print $$2 }' | grep -E '^[A-F0-9]+$$' || echo "-")

.PHONY: all clean whisper setup build local check healthcheck help dev run reload test acceptance dmg

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project Sotto.xcodeproj -scheme Sotto -configuration Debug CODE_SIGN_IDENTITY="" build

# Build for local use without Apple Developer certificate
local: check setup
	@echo "Building Sotto for local use..."
	@if [ "$(LOCAL_SIGN_IDENTITY)" = "-" ]; then \
		echo "  Signing: ad-hoc (Accessibility/Input Monitoring permissions reset on each rebuild)"; \
	else \
		echo "  Signing: $(LOCAL_SIGN_IDENTITY) (stable cdhash; permissions persist across rebuilds)"; \
	fi
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project Sotto.xcodeproj -scheme Sotto -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		-skipMacroValidation \
		'CODE_SIGN_IDENTITY=$(LOCAL_SIGN_IDENTITY)' \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		ENABLE_HARDENED_RUNTIME=NO \
		CODE_SIGN_ENTITLEMENTS=$(CURDIR)/Sotto/Sotto.local.entitlements \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/Sotto.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Killing running Sotto instance before install (avoids dup-process global-shortcut hijack)..."; \
		/usr/bin/killall Sotto 2>/dev/null || true; \
		sleep 0.3; \
		echo "Copying Sotto.app to /Applications..."; \
		rm -rf "/Applications/Sotto.app"; \
		ditto "$$APP_PATH" "/Applications/Sotto.app"; \
		xattr -cr "/Applications/Sotto.app"; \
		echo ""; \
		echo "Build complete! App saved to: /Applications/Sotto.app"; \
		echo "Run with: open -a Sotto  (or Spotlight / Launchpad)"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built Sotto.app at $$APP_PATH"; \
		exit 1; \
	fi

# Package a shareable DMG from the local build (reuses `make local`'s known-good
# app). Self-signed, NOT notarized: friends must clear quarantine once with
#   xattr -dr com.apple.quarantine /Applications/Sotto.app
# Output: dist/Sotto.dmg
dmg: local
	@bash scripts/make-dmg.sh

# Reload: build, kill the running instance, relaunch. Use this during dev so you
# don't have to manually quit + reopen. Incremental build is ~5-15s after first.
reload: local
	@echo "Killing running Sotto instance (if any)..."
	@/usr/bin/killall Sotto 2>/dev/null || true
	@sleep 0.3
	@echo "Launching /Applications/Sotto.app..."
	@open "/Applications/Sotto.app"

# Run the unit test suite headlessly. One thing makes `xcodebuild test` work on
# this repo that a plain `xcodebuild test` gets wrong:
#   AppRuntimeMode auto-detects XCTestCase (+ SOTTO_HEADLESS_TESTS=1) and sets
#   activation policy .prohibited, so the test host never steals focus.
# (The dictionary store's CloudKit mirror is unconditionally off now, so it no
# longer depends on LOCAL_BUILD being set here.)
# Separate DerivedData so a test run never clobbers `make local`'s install build.
TEST_DERIVED_DATA := $(CURDIR)/.local-build-test
# Generated acceptance tests live in the SottoTests target but are NOT unit
# tests: they run only through `make acceptance` (bin/acceptance), which parses
# the features and regenerates them first. Skipping them here keeps the two
# suites separate.
ACCEPTANCE_SKIPS := $(shell sed -n 's/^final class \([A-Za-z0-9_]*\).*/-skip-testing:SottoTests\/\1/p' SottoTests/Generated/GeneratedAcceptanceTests.swift 2>/dev/null)
# Sign the test host with the SAME stable identity as `make local` (not ad-hoc).
# Ad-hoc (`-`) gives the test-host app a fresh cdhash every run, so macOS treats
# it as a new app and re-prompts for Accessibility / Input Monitoring / etc. on
# every `make test`. Using the stable `sotto-local` cert keeps the
# designated requirement constant → permissions persist across test runs.
# Falls back to ad-hoc automatically when the cert is absent (LOCAL_SIGN_IDENTITY=-).
test: check setup
	@echo "Running SottoTests headlessly (non-activating)..."
	SOTTO_HEADLESS_TESTS=1 xcodebuild test \
		-project Sotto.xcodeproj -scheme Sotto -configuration Debug \
		-derivedDataPath "$(TEST_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		-only-testing:SottoTests \
		$(ACCEPTANCE_SKIPS) \
		-skipMacroValidation \
		'CODE_SIGN_IDENTITY=$(LOCAL_SIGN_IDENTITY)' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" ENABLE_HARDENED_RUNTIME=NO \
		CODE_SIGN_ENTITLEMENTS=$(CURDIR)/Sotto/Sotto.local.entitlements \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		-quiet

# Run the Gherkin acceptance pipeline: parse features, snapshot project facts,
# generate the executable tests, run only those.
acceptance:
	@bash bin/acceptance

# Run application
run:
	@if [ -d "/Applications/Sotto.app" ]; then \
		echo "Opening /Applications/Sotto.app..."; \
		open "/Applications/Sotto.app"; \
	else \
		echo "Looking for Sotto.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "Sotto.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "Sotto.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to Sotto project"
	@echo "  build              Build the Sotto Xcode project"
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  run                Launch the built Sotto app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  test               Run the unit test suite headlessly"
	@echo "  acceptance         Run the Gherkin acceptance pipeline"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"