# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Sotto ships macOS only. Upstream build-xcframework.sh builds every Apple platform and leaves ~5 GB of build-* intermediates; keep only build-apple.
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
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh && rm -rf build-ios-* build-tvos-* build-visionos* build-macos; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

llama:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(LLAMA_FRAMEWORK_PATH)" ]; then \
		echo "Building llama.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(LLAMA_CPP_DIR)" ]; then \
			git clone https://github.com/ggml-org/llama.cpp $(LLAMA_CPP_DIR); \
		else \
			(cd $(LLAMA_CPP_DIR) && git pull); \
		fi; \
		cd $(LLAMA_CPP_DIR) && ./build-xcframework.sh macos && rm -rf build-macos; \
	else \
		echo "llama.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

# Clang merges duplicate C types across modules only when headers are byte-identical,
# or the build fails with type redefinition errors. Swift calls only whisper_*
# functions, never ggml, so newer ggml headers from llama are safe in whisper.
ggml-headers: whisper llama
	@set -e; \
	needs_copy=0; \
	for slice_dir in $(FRAMEWORK_PATH)/macos-*/; do \
		slice_dir="$${slice_dir%/}"; \
		slice=$$(basename "$$slice_dir"); \
		w_hdr=$$(realpath "$$slice_dir/whisper.framework/Headers" 2>/dev/null); \
		l_hdr=$$(realpath "$(LLAMA_FRAMEWORK_PATH)/$$slice/llama.framework/Headers" 2>/dev/null); \
		[ -d "$$w_hdr" ] || continue; \
		[ -d "$$l_hdr" ] || { echo "Error: llama headers not found for slice $$slice: $$l_hdr" >&2; exit 1; }; \
		for f in "$$l_hdr"/ggml*.h "$$l_hdr"/gguf.h; do \
			[ -f "$$f" ] || continue; \
			wf="$$w_hdr/$$(basename "$$f")"; \
			if [ ! -f "$$wf" ] || ! cmp -s "$$f" "$$wf"; then \
				needs_copy=1; \
				break 2; \
			fi; \
		done; \
	done; \
	if [ "$$needs_copy" -eq 0 ]; then \
		echo "ggml headers already identical"; \
		exit 0; \
	fi; \
	for slice_dir in $(FRAMEWORK_PATH)/macos-*/; do \
		slice_dir="$${slice_dir%/}"; \
		slice=$$(basename "$$slice_dir"); \
		w_hdr=$$(realpath "$$slice_dir/whisper.framework/Headers" 2>/dev/null); \
		l_hdr=$$(realpath "$(LLAMA_FRAMEWORK_PATH)/$$slice/llama.framework/Headers" 2>/dev/null); \
		[ -d "$$w_hdr" ] || continue; \
		[ -d "$$l_hdr" ] || { echo "Error: llama headers not found for slice $$slice: $$l_hdr" >&2; exit 1; }; \
		cp -f "$$l_hdr"/ggml*.h "$$l_hdr"/gguf.h "$$w_hdr/"; \
		for f in "$$l_hdr"/ggml*.h "$$l_hdr"/gguf.h; do \
			[ -f "$$f" ] || continue; \
			wf="$$w_hdr/$$(basename "$$f")"; \
			if ! cmp -s "$$f" "$$wf"; then \
				echo "Error: ggml header mismatch after copy: $$wf differs from $$f" >&2; \
				exit 1; \
			fi; \
		done; \
	done; \
	echo "Synced ggml headers from llama.xcframework to whisper.xcframework"

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

setup: whisper llama ggml-headers vad-model
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "llama framework is ready at $(LLAMA_FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project Sotto.xcodeproj -scheme Sotto -configuration Debug CODE_SIGN_IDENTITY="" build
