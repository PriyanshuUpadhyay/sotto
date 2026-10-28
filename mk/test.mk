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

