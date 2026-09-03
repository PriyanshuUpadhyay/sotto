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

.PHONY: all clean whisper vad-model setup build local check healthcheck help dev run reload test eval acceptance acceptance-mutate property dmg release publish

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
		echo "SHA-256 (paste into the release notes):"; \
		shasum -a 256 "$(RELEASE_DIR)/Sotto-$$V.dmg" | awk '{ print "  " $$1 }'; \
		echo ""; \
		echo "To publish:  make publish NOTES=path/to/notes.md"

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
#
# `test` and `eval` share one lock and one gate file. The unit suite must never
# reach the enhancement eval, which makes real on-device model calls: the eval
# gate is what enables it, so a present gate — an eval running now, or one that
# was interrupted before its trap could clear it — is a hard refusal here, not a
# warning. The lock is a directory because mkdir(2) is the atomic primitive
# every shell has; macOS ships no flock(1).
EVAL_GATE := $(CURDIR)/eval/results/.eval-run.json
SUITE_LOCK := $(CURDIR)/eval/results/.suite.lock
# Acquire the lock, reclaiming it from an owner that is gone. A SIGKILL or a
# host restart skips the trap and would otherwise leave the lock blocking both
# targets forever. `kill -0` answers "live" for a process we own; when it says
# no, `ps -p` separates "really gone" from "alive but not ours to signal", and
# only the first is reclaimed. Kept to ONE line so it can be spliced into the
# recipe line that also arms the trap — they must share a shell.
ACQUIRE_LOCK = mkdir "$(SUITE_LOCK)" 2>/dev/null || { owner=$$(cat "$(SUITE_LOCK)/pid" 2>/dev/null); case "$$owner" in ''|*[!0-9]*) echo "suite lock has no readable owner - delete it to recover: $(SUITE_LOCK)"; exit 1;; esac; if kill -0 "$$owner" 2>/dev/null || ps -p "$$owner" >/dev/null 2>&1; then echo "another make test/eval is running (pid $$owner) - lock: $(SUITE_LOCK)"; exit 1; fi; echo "reclaiming the suite lock from dead pid $$owner"; rm -rf "$(SUITE_LOCK)"; mkdir "$(SUITE_LOCK)" 2>/dev/null || { echo "could not reclaim the suite lock - delete it to recover: $(SUITE_LOCK)"; exit 1; }; }
test: check setup
	@mkdir -p "$(dir $(EVAL_GATE))"
	@if [ -e "$(EVAL_GATE)" ]; then \
		echo "refusing to run: the enhancement-eval gate is present."; \
		echo "  $(EVAL_GATE)"; \
		echo "An eval is running, or one was interrupted. Wait for it, or delete that file."; \
		exit 1; \
	fi
	@$(ACQUIRE_LOCK); \
	echo $$$$ > "$(SUITE_LOCK)/pid"; \
	trap 'rm -rf "$(SUITE_LOCK)"' EXIT INT TERM; \
	echo "Running SottoTests headlessly (non-activating)..."; \
	status=0; \
	SOTTO_HEADLESS_TESTS=1 xcodebuild test $(LOCAL_XCODE_FLAGS) \
		-derivedDataPath "$(TEST_DERIVED_DATA)" \
		-only-testing:SottoTests \
		$(ACCEPTANCE_SKIPS) \
		$(PROPERTY_SKIPS) \
		-quiet || status=$$?; \
	exit $$status

# Run the enhancement quality/latency eval against the REAL production path
# (prompt assembly -> AFM -> output filter -> repair guard -> mechanics).
# Every row is a live on-device model call, so it never runs under `make test`:
# the harness is gated on $(EVAL_GATE), written here and removed by the trap on
# any exit, including an interrupt.
#   make eval LABEL=round3-1                   (guided generation: the app default)
#   make eval LABEL=probe-guided GUIDED=true   (force it on, to re-check the verdict)
#   make eval LABEL=it01 SET=dev               (score the tuning set instead)
# Results: eval/results/<UTC-timestamp>-<LABEL>.{json,md}; the AFM timings CSV
# is redirected alongside them so it never touches the user's app data.
#
# LABEL is restricted to [A-Za-z0-9._-]+ with no "..": it becomes a path
# component (the timings directory, the result filenames) and a JSON string
# value, and that character set needs no escaping in either. Both values reach
# the recipe through the environment, never spliced into the shell line, so a
# quote or a semicolon in one can never be parsed as script.
LABEL ?= unlabeled
GUIDED ?=
# Which fixture to score. `eval` is the original synthetic set and the default,
# so a bare `make eval` measures exactly what it always did. `dev` is the tuning
# set; `heldout` is scored once, at the end. Validated the same way LABEL is,
# before the lock and the gate exist, and again inside the harness.
SET ?= eval
export SOTTO_EVAL_LABEL := $(LABEL)
export SOTTO_EVAL_GUIDED := $(GUIDED)
export SOTTO_EVAL_SET := $(SET)
eval: check setup
	@printf '%s' "$$SOTTO_EVAL_LABEL" | grep -Eq '^[A-Za-z0-9._-]+$$' || { \
		echo "LABEL must match [A-Za-z0-9._-]+ and must not contain '..'"; exit 1; }
	@case "$$SOTTO_EVAL_LABEL" in *..*) \
		echo "LABEL must match [A-Za-z0-9._-]+ and must not contain '..'"; exit 1;; esac
	@[ -z "$$SOTTO_EVAL_GUIDED" ] || [ "$$SOTTO_EVAL_GUIDED" = true ] \
		|| [ "$$SOTTO_EVAL_GUIDED" = false ] || { \
		echo "GUIDED must be exactly true or false"; exit 1; }
	@[ "$$SOTTO_EVAL_SET" = eval ] || [ "$$SOTTO_EVAL_SET" = dev ] \
		|| [ "$$SOTTO_EVAL_SET" = heldout ] || { \
		echo "SET must be exactly eval, dev or heldout"; exit 1; }
	@test -f "$(CURDIR)/eval/data/enhancement-$$SOTTO_EVAL_SET.jsonl" || { \
		echo "no fixture for SET=$$SOTTO_EVAL_SET: $(CURDIR)/eval/data/enhancement-$$SOTTO_EVAL_SET.jsonl"; exit 1; }
	@mkdir -p "$(dir $(EVAL_GATE))"
	@$(ACQUIRE_LOCK); \
	echo $$$$ > "$(SUITE_LOCK)/pid"; \
	trap 'rm -f "$(EVAL_GATE)"; rm -rf "$(SUITE_LOCK)"' EXIT INT TERM; \
	echo "Running enhancement eval (label=$$SOTTO_EVAL_LABEL, set=$$SOTTO_EVAL_SET, guided=$${SOTTO_EVAL_GUIDED:-app default})..."; \
	printf '{"label":"%s","set":"%s"%s}' "$$SOTTO_EVAL_LABEL" "$$SOTTO_EVAL_SET" \
		"$${SOTTO_EVAL_GUIDED:+,\"guided\":$$SOTTO_EVAL_GUIDED}" > "$(EVAL_GATE)"; \
	status=0; \
	SOTTO_HEADLESS_TESTS=1 SOTTO_EVAL=1 \
		xcodebuild test $(LOCAL_XCODE_FLAGS) \
		-derivedDataPath "$(TEST_DERIVED_DATA)" \
		-only-testing:SottoTests/EnhancementEvalTests \
		-parallel-testing-enabled NO \
		-quiet || status=$$?; \
	exit $$status

# Publish what `make release` prepared. Kept separate so a build never ships
# by accident, and so the ordering is enforced rather than remembered: the
# release asset must exist before the appcast pointing at it reaches the feed,
# or an updater polling in between downloads a 404.
publish:
	@set -e; \
		[ -n "$(NOTES)" ] || { echo "usage: make publish NOTES=path/to/notes.md"; exit 1; }; \
		test -f "$(NOTES)" || { echo "notes file not found: $(NOTES)"; exit 1; }; \
		DMG=$$(ls "$(RELEASE_DIR)"/Sotto-*.dmg 2>/dev/null | head -1); \
		[ -n "$$DMG" ] || { echo "no DMG in $(RELEASE_DIR) - run make release first"; exit 1; }; \
		V=$$(basename "$$DMG" .dmg | sed "s/^Sotto-//"); \
		grep -q "releases/download/v$$V/" docs/appcast.xml \
			|| { echo "docs/appcast.xml does not name v$$V - re-run make release"; exit 1; }; \
		gh release view "v$$V" --repo $(GITHUB_REPO) >/dev/null 2>&1 \
			&& { echo "release v$$V already exists - bump the version first"; exit 1; }; \
		echo "Creating release v$$V with $$DMG..."; \
		gh release create "v$$V" "$$DMG" --repo $(GITHUB_REPO) --title "v$$V" --notes-file "$(NOTES)"; \
		echo "Asset is live. Publishing the appcast..."; \
		git add docs/appcast.xml; \
		git diff --cached --quiet || git commit -m "Publish $$V"; \
		git push; \
		echo ""; \
		echo "Published v$$V. The feed updates when GitHub Pages redeploys (~15s)."

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
	@echo "  eval               Run the enhancement eval (make eval LABEL=baseline-1)"
	@echo "  acceptance         Run the Gherkin acceptance pipeline"
	@echo "  acceptance-mutate  Mutate feature example values and check the scenarios catch it"
	@echo "  property           Run the property tests (Swift + acceptance pipeline)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"