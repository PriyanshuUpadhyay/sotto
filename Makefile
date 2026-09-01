# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/Sotto-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build

# Silero VAD model: third-party MIT weights, fetched instead of vendored.
# Xcode synchronized folders bundle whatever is on disk, so an absent file
# builds an app with VAD silently off. The checksum gate makes that loud.
VAD_MODEL := $(CURDIR)/Sotto/Resources/models/ggml-silero-v5.1.2.bin
VAD_MODEL_URL := https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin
VAD_MODEL_SHA := 29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf

# Release packaging. The EdDSA signature, not an Apple certificate, is what an
# installed copy checks before it accepts an update, so the private key in the
# login keychain is the only credential `make release` needs.
SPARKLE_BIN := $(LOCAL_DERIVED_DATA)/SourcePackages/artifacts/sparkle/Sparkle/bin
RELEASE_DIR := $(CURDIR)/dist/releases
GITHUB_REPO := PriyanshuUpadhyay/sotto

# Local-build signing identity. scripts/local-sign-identity.sh explains the
# cert and how to create it; bin/acceptance reads the identity from there too,
# so every local invocation signs the same way.
#
# Override with: make local LOCAL_SIGN_IDENTITY="other-name" — exact name or SHA1.
LOCAL_SIGN_IDENTITY ?= $(shell bash $(CURDIR)/scripts/local-sign-identity.sh)

# Shared by every local xcodebuild invocation below. Signing has to match across
# `local`, `test`, and `property`: a run that signs differently gets a different
# cdhash and re-prompts for Accessibility / Input Monitoring.
LOCAL_XCODE_FLAGS = -project Sotto.xcodeproj -scheme Sotto -configuration Debug \
	-xcconfig LocalBuild.xcconfig \
	-skipMacroValidation \
	'CODE_SIGN_IDENTITY=$(LOCAL_SIGN_IDENTITY)' \
	CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
	DEVELOPMENT_TEAM="" ENABLE_HARDENED_RUNTIME=NO \
	CODE_SIGN_ENTITLEMENTS=$(CURDIR)/Sotto/Sotto.local.entitlements \
	SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD'

.PHONY: all clean whisper vad-model setup build local check healthcheck help dev run reload test acceptance acceptance-mutate property dmg release

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

vad-model:
	@if [ -f "$(VAD_MODEL)" ] && [ "$$(shasum -a 256 "$(VAD_MODEL)" | awk '{print $$1}')" = "$(VAD_MODEL_SHA)" ]; then \
		echo "VAD model present"; \
	else \
		echo "Fetching Silero VAD model..."; \
		mkdir -p "$(dir $(VAD_MODEL))"; \
		curl -fL --retry 3 --connect-timeout 20 -o "$(VAD_MODEL).tmp" "$(VAD_MODEL_URL)" \
			|| { rm -f "$(VAD_MODEL).tmp"; echo "VAD model download failed: $(VAD_MODEL_URL)"; exit 1; }; \
		got=$$(shasum -a 256 "$(VAD_MODEL).tmp" | awk '{print $$1}'); \
		if [ "$$got" != "$(VAD_MODEL_SHA)" ]; then \
			rm -f "$(VAD_MODEL).tmp"; \
			echo "VAD model checksum mismatch"; \
			echo "  expected $(VAD_MODEL_SHA)"; \
			echo "  got      $$got"; \
			exit 1; \
		fi; \
		mv "$(VAD_MODEL).tmp" "$(VAD_MODEL)"; \
		echo "VAD model ready"; \
	fi

setup: whisper vad-model
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
	xcodebuild $(LOCAL_XCODE_FLAGS) \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
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
		echo "  - Not notarized: a recipient clears quarantine once (see scripts/make-dmg.sh)"; \
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

# Build a signed, publishable release from the `make local` app. Prepares
# artifacts only — publishing stays an explicit act, printed at the end.
#
# RELEASE_DIR is emptied each run so the generated appcast holds exactly one
# item. Sparkle only needs the newest one, and a stale item would otherwise
# carry this run's download-url-prefix and point at the wrong tag.
release: local
	@set -e; \
		APP="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/Sotto.app"; \
		V=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$$APP/Contents/Info.plist"); \
		[ -n "$$V" ] || { echo "could not read CFBundleShortVersionString"; exit 1; }; \
		rm -rf "$(RELEASE_DIR)"; mkdir -p "$(RELEASE_DIR)"; \
		OUT_DIR="$(RELEASE_DIR)" bash scripts/make-dmg.sh >/dev/null; \
		mv "$(RELEASE_DIR)/Sotto.dmg" "$(RELEASE_DIR)/Sotto-$$V.dmg"; \
		"$(SPARKLE_BIN)/generate_appcast" \
			--download-url-prefix "https://github.com/$(GITHUB_REPO)/releases/download/v$$V/" \
			--link "https://github.com/$(GITHUB_REPO)" \
			"$(RELEASE_DIR)"; \
		grep -q "sparkle:edSignature" "$(RELEASE_DIR)/appcast.xml" \
			|| { echo "appcast is UNSIGNED — is the EdDSA key in the login keychain?"; exit 1; }; \
		cp "$(RELEASE_DIR)/appcast.xml" docs/appcast.xml; \
		echo ""; \
		echo "Release $$V prepared and signed:"; \
		echo "  $(RELEASE_DIR)/Sotto-$$V.dmg"; \
		echo "  docs/appcast.xml"; \
		echo ""; \
		echo "To publish:"; \
		echo "  gh release create v$$V \"$(RELEASE_DIR)/Sotto-$$V.dmg\" --title v$$V --notes-file <notes>"; \
		echo "  git add docs/appcast.xml && git commit -m \"Publish $$V\" && git push"; \
		echo ""; \
		echo "Order matters: create the release first, or the appcast points at a missing asset."

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
# `bb clojure` resolves deps through the JVM, and macOS ships no JDK, so find
# one the same way the signing identity is found: use what the environment
# already set, else ask java_home, else the Homebrew install.
JAVA_HOME ?= $(shell /usr/libexec/java_home 2>/dev/null || echo /opt/homebrew/opt/openjdk)
# Generated acceptance tests live in the SottoTests target but are NOT unit
# tests: they run only through `make acceptance` (bin/acceptance), which parses
# the features and regenerates them first. Skipping them here keeps the two
# suites separate.
ACCEPTANCE_SKIPS := $(shell sed -n 's/^final class \([A-Za-z0-9_]*\).*/-skip-testing:SottoTests\/\1/p' SottoTests/Generated/GeneratedAcceptanceTests.swift 2>/dev/null)
# Property tests are randomized checks over invariants, not unit tests, so they
# stay out of the unit suite (and out of coverage and mutation with it). Run
# them with `make property`.
PROPERTY_CLASSES := $(shell sed -n 's/^final class \([A-Za-z0-9_]*\).*/\1/p' SottoTests/Property/*.swift 2>/dev/null)
PROPERTY_SKIPS := $(addprefix -skip-testing:SottoTests/,$(PROPERTY_CLASSES))
PROPERTY_ONLY := $(addprefix -only-testing:SottoTests/,$(PROPERTY_CLASSES))
# Sign the test host with the SAME stable identity as `make local` (not ad-hoc).
# Ad-hoc (`-`) gives the test-host app a fresh cdhash every run, so macOS treats
# it as a new app and re-prompts for Accessibility / Input Monitoring / etc. on
# every `make test`. Using the stable `sotto-local` cert keeps the
# designated requirement constant → permissions persist across test runs.
# Falls back to ad-hoc automatically when the cert is absent (LOCAL_SIGN_IDENTITY=-).
test: check setup
	@echo "Running SottoTests headlessly (non-activating)..."
	SOTTO_HEADLESS_TESTS=1 xcodebuild test $(LOCAL_XCODE_FLAGS) \
		-derivedDataPath "$(TEST_DERIVED_DATA)" \
		-only-testing:SottoTests \
		$(ACCEPTANCE_SKIPS) \
		$(PROPERTY_SKIPS) \
		-quiet

# Run the Gherkin acceptance pipeline: parse features, snapshot project facts,
# generate the executable tests, run only those.
acceptance:
	@bash bin/acceptance

# Run the property tests: the Swift invariants over the app's pure logic, then
# the Babashka acceptance pipeline's own. Separate from `make test` on purpose.
# A failing property names the seed and the input that broke it; `-quiet` keeps
# that in the result bundle, so read it there or rerun this target without it.
property:
	@echo "Running Swift property tests..."
	SOTTO_HEADLESS_TESTS=1 xcodebuild test $(LOCAL_XCODE_FLAGS) \
		-derivedDataPath "$(TEST_DERIVED_DATA)" \
		$(PROPERTY_ONLY) \
		-quiet
	@echo "Running acceptance pipeline property specs..."
	@command -v bb >/dev/null 2>&1 || { echo "bb (Babashka) is not installed"; exit 1; }
	@cd acceptance && JAVA_HOME="$(JAVA_HOME)" PATH="$(JAVA_HOME)/bin:$$PATH" bb clojure -M:property

# Gherkin acceptance mutation: mutate the example values in features/ and check
# that the acceptance scenarios notice. Builds the test bundle once, then each
# mutation only repoints the runtime at its mutated IR.
# One worker by default; each one runs a full xcodebuild test host.
acceptance-mutate:
	@WORKERS=$(WORKERS) bash bin/acceptance-mutate $(LEVEL)

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
	@echo "  acceptance-mutate  Mutate feature example values and check the scenarios catch it"
	@echo "  property           Run the property tests (Swift + acceptance pipeline)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"