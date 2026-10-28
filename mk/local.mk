
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

