# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/Sotto-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LLAMA_CPP_DIR := $(DEPS_DIR)/llama.cpp
LLAMA_FRAMEWORK_PATH := $(LLAMA_CPP_DIR)/build-apple/llama.xcframework
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

.PHONY: all clean whisper llama ggml-headers vad-model setup build local check healthcheck help dev run reload test eval acceptance acceptance-mutate property dmg release publish

# Default target
all: check build

# Development workflow
dev: build run

include mk/deps.mk
include mk/local.mk
include mk/test.mk
include mk/release.mk
