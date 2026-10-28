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
	@echo "  llama              Clone and build llama.cpp XCFramework"
	@echo "  ggml-headers       Sync ggml headers from llama to whisper xcframework"
	@echo "  setup              Copy whisper XCFramework to Sotto project"
	@echo "  build              Build the Sotto Xcode project"
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  run                Launch the built Sotto app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  test               Run the unit test suite headlessly"
	@echo "  eval               Run the enhancement eval (make eval LABEL=baseline-1)"
	@echo "  dmg                Package the local build into dist/Sotto.dmg (needs uv)"
	@echo "  release            Build and sign a release DMG + appcast in dist/releases"
	@echo "  publish            Upload the prepared release (make publish NOTES=notes.md)"
	@echo "  acceptance         Run the Gherkin acceptance pipeline"
	@echo "  acceptance-mutate  Mutate feature example values and check the scenarios catch it"
	@echo "  property           Run the property tests (Swift + acceptance pipeline)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
