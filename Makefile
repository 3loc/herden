# Task runner for Herden. Typical flows:
#   make install                 # build Debug and run it on the connected iPhone
#   make bump && make testflight # interim TestFlight build, no version cut
#   make publish                 # cut a release: see docs/guides/releasing.md

PROJECT := Herden.xcodeproj
SCHEME  := Herden
ARCHIVE := build/Herden.xcarchive
APP_ID  := ltd.3loc.herden
SIM     ?= iPhone 17
IOS_WATCH_DEBOUNCE ?= 1s

# Stable caches survive task worktrees and Studio staging directories. Xcode's
# default DerivedData key includes the checkout path, which previously created
# a fresh ~800 MB Herden cache for every temporary checkout. Cargo's default
# `runtime/target` had the same problem and could fill a tmpfs worktree.
HERDEN_CACHE_ROOT ?= $(if $(strip $(XDG_CACHE_HOME)),$(XDG_CACHE_HOME),$(HOME)/.cache)/herden-build
CARGO_TARGET_DIR ?= $(HERDEN_CACHE_ROOT)/cargo-target
DERIVED ?= $(HOME)/Library/Developer/Xcode/DerivedData/Herden-Local
SSH_DERIVED ?= $(HOME)/Library/Developer/Xcode/DerivedData/HerdenSSH-Local
SOURCE_PACKAGES ?= $(HERDEN_CACHE_ROOT)/source-packages
XCODE_PACKAGE_ARGS = -clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" $(XCODE_RESOLUTION_ARGS)
export CARGO_TARGET_DIR
export HERDEN_SSH_DERIVED_DATA := $(SSH_DERIVED)

# Keep the signing team out of the public project. Maintainers can place
# `DEVELOPMENT_TEAM = ABCDE12345` in the ignored .herden.local.mk once, or pass
# it to make explicitly. Simulator builds do not need it.
-include .herden.local.mk
DEVELOPMENT_TEAM ?= $(HERDEN_DEVELOPMENT_TEAM)
SIGNING_ARGS = $(if $(strip $(DEVELOPMENT_TEAM)),DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM),)

# First physical device paired with devicectl; override with `make install DEVICE=<uuid>`.
DEVICE ?= $(shell xcrun devicectl list devices 2>/dev/null | awk '/physical[a-z]* *$$/ { for (i = 1; i <= NF; i++) if ($$i ~ /^[0-9A-Fa-f-]{36}$$/) { print $$i; exit } }')
IOS_BUILD_DESTINATION ?= generic/platform=iOS
IOS_SIGNING_ARGS ?=

.PHONY: help generate build prepare-ios-cache ios-build ios-build-sim test ios-test ios-test-one ios-test-ssh ios-test-all test-all install install-built watch-ios-device sim archive upload testflight bump publish clean check-device cache-info ssh-artifacts verify-ssh-artifacts

help: ## Show available targets
	@awk -F':.*## ' '/^[a-z-]+:.*## / { printf "  make %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: host-build host-install host-check host-test host-test-one host-perf host-release host-release-asset host-release-assemble

# Pinned Zig 0.15.2 cannot link its build runner against Xcode 26's macOS SDK.
# On macOS, route only the SDK-path lookup through the compatible CLT 15.4 SDK.
HOST_BUILD_ENV = $(if $(filter Darwin,$(shell uname -s)),HERDEN_REAL_XCRUN="$(shell command -v xcrun)" PATH="$(CURDIR)/scripts/macos15-sdk-bin:$(PATH)",)

host-build: ## Compile only the Rust Host runtime
	cd runtime && $(HOST_BUILD_ENV) cargo build --locked

host-test: ## Run the locked Host suite serially (avoids upstream parallel fixture races)
	cd runtime && $(HOST_BUILD_ENV) cargo test --locked -- --test-threads=1

host-test-one: ## Run one Host test substring (FILTER=test_name)
	@test -n "$(FILTER)" || { echo "FILTER is required" >&2; exit 2; }
	cd runtime && $(HOST_BUILD_ENV) cargo test --locked "$(FILTER)" -- --test-threads=1

host-perf: ## Compare candidate and published Host CPU use (HOST_CANDIDATE=... HOST_BASELINE=...)
	@test -n "$(HOST_CANDIDATE)" -a -n "$(HOST_BASELINE)" || { echo "HOST_CANDIDATE and HOST_BASELINE are required" >&2; exit 2; }
	cd runtime && HERDR_PERF_BASELINE_BIN="$(HOST_BASELINE)" bash scripts/release_perf_smoke.sh "$(HOST_CANDIDATE)"

host-install: ## Build and install the native Host on this Linux or macOS machine
	sh scripts/install-host-source.sh

host-check: ## Check Host source-build prerequisites without installing anything
	sh scripts/install-host-source.sh --check

host-release-asset: ## Build one Host release asset (TARGET=... OUT_DIR=...)
	@test -n "$(TARGET)" || { echo "TARGET is required" >&2; exit 2; }
	@test -n "$(OUT_DIR)" || { echo "OUT_DIR is required" >&2; exit 2; }
	$(HOST_BUILD_ENV) sh scripts/build-host-release-asset.sh "$(TARGET)" "$(OUT_DIR)"

host-release: ## Build/resume all four Host assets and metadata (HOST_VERSION=... OUT_DIR=...)
	@test -n "$(HOST_VERSION)" || { echo "HOST_VERSION is required" >&2; exit 2; }
	@test -n "$(OUT_DIR)" || { echo "OUT_DIR is required" >&2; exit 2; }
	$(HOST_BUILD_ENV) sh scripts/build-host-release.sh "$(HOST_VERSION)" "$(OUT_DIR)"

host-release-assemble: ## Assemble Host release metadata (HOST_VERSION=... OUT_DIR=...)
	@test -n "$(HOST_VERSION)" || { echo "HOST_VERSION is required" >&2; exit 2; }
	@test -n "$(OUT_DIR)" || { echo "OUT_DIR is required" >&2; exit 2; }
	sh scripts/assemble-host-release.sh "$(HOST_VERSION)" "$(OUT_DIR)"

ssh-artifacts: ## Rebuild the pinned HerdenSSH XCFrameworks
	Packages/HerdenSSH/Scripts/build-native.sh

verify-ssh-artifacts: ## Verify HerdenSSH artifact hashes, slices, and policy
	Packages/HerdenSSH/Scripts/verify-native.sh

generate: ## Regenerate the Xcode project from project.yml (XcodeGen)
	xcodegen generate

build: ios-build ## Compatibility alias for ios-build

prepare-ios-cache:
	@mkdir -p "$(SOURCE_PACKAGES)"

ios-build: prepare-ios-cache ## Build only the iOS app for a physical device
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination '$(IOS_BUILD_DESTINATION)' -derivedDataPath "$(DERIVED)" \
		$(XCODE_PACKAGE_ARGS) \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		$(SIGNING_ARGS) $(IOS_SIGNING_ARGS) build

ios-build-sim: prepare-ios-cache ## Compile only the iOS app for the simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=iOS Simulator,name=$(SIM)' \
		-derivedDataPath "$(DERIVED)" $(XCODE_PACKAGE_ARGS) build

test: ios-test-all ## Compatibility alias for the complete iOS test surface

ios-test: prepare-ios-cache ## Run only the iOS app tests (skip the separate HerdenSSH suite)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIM)' \
		-derivedDataPath "$(DERIVED)" $(XCODE_PACKAGE_ARGS) test

ios-test-one: prepare-ios-cache ## Run one iOS suite (SUITE=PairingCodeTests)
	@test -n "$(SUITE)" || { echo "SUITE is required" >&2; exit 2; }
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIM)' \
		-derivedDataPath "$(DERIVED)" \
		$(XCODE_PACKAGE_ARGS) \
		-only-testing:HerdenTests/$(SUITE)

ios-test-ssh: ## Run only the repository-local HerdenSSH package tests
	scripts/run-herdenssh-package-tests.sh 'platform=iOS Simulator,name=$(SIM)'

ios-test-all: ios-test ios-test-ssh ## Run both iOS test surfaces

test-all: host-test ios-test-all ## Run Host and iOS suites; use only before cross-product/release work

check-device:
	@test -n "$(DEVICE)" || { echo "No physical device found; pass DEVICE=<devicectl uuid>"; exit 1; }

install: check-device build ## Build Debug, install on the iPhone, and relaunch it
	xcrun devicectl device install app --device $(DEVICE) \
		$(DERIVED)/Build/Products/Debug-iphoneos/Herden.app
	xcrun devicectl device process launch --terminate-existing --device $(DEVICE) $(APP_ID)

install-built: check-device ## Install/relaunch an already-built Debug app without invoking Xcode
	@test -d "$(DERIVED)/Build/Products/Debug-iphoneos/Herden.app" || { \
		echo "No built app in $(DERIVED); run make ios-build first" >&2; exit 1; \
	}
	xcrun devicectl device install app --device $(DEVICE) \
		$(DERIVED)/Build/Products/Debug-iphoneos/Herden.app
	xcrun devicectl device process launch --terminate-existing --device $(DEVICE) $(APP_ID)

watch-ios-device: ## Watch iOS code and install to a connected iPhone/iPad
	@command -v watchexec >/dev/null || { echo "watchexec not found. Install with: brew install watchexec"; exit 1; }
	watchexec \
		--watch Sources \
		--watch Packages/HerdenSSH/Sources \
		--watch Packages/HerdenSSH/NativeSupport \
		--watch Packages/HerdenSSH/Package.swift \
		--watch project.yml \
		--exts swift,h,modulemap,yml,plist,xcprivacy,entitlements,resolved,json,png,ttf \
		--debounce "$(IOS_WATCH_DEBOUNCE)" \
		--on-busy-update queue \
		-- make install DEVICE="$(DEVICE)"

sim: prepare-ios-cache ## Build Debug and run it on the simulator (override with SIM=<name>)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath "$(DERIVED)" \
		$(XCODE_PACKAGE_ARGS) build
	xcrun simctl boot '$(SIM)' 2>/dev/null || true
	open -a Simulator
	xcrun simctl install booted $(DERIVED)/Build/Products/Debug-iphonesimulator/Herden.app
	xcrun simctl launch --terminate-running-process booted $(APP_ID)

archive: prepare-ios-cache ## Archive a Release build for distribution
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' -archivePath $(ARCHIVE) \
		-derivedDataPath "$(DERIVED)" \
		$(XCODE_PACKAGE_ARGS) \
		-allowProvisioningUpdates $(SIGNING_ARGS) archive

upload: ## Upload the existing archive to App Store Connect (TestFlight)
	scripts/upload-testflight.sh

testflight: archive upload ## Archive and upload in one go

bump: ## Increment CURRENT_PROJECT_VERSION in project.yml (app + extension stay in lockstep)
	@CUR=$$(awk -F'"' '/CURRENT_PROJECT_VERSION/ { print $$2; exit }' project.yml); \
	NEW=$$((CUR + 1)); \
	sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[0-9]+\"/CURRENT_PROJECT_VERSION: \"$$NEW\"/g" project.yml; \
	echo "CURRENT_PROJECT_VERSION: $$CUR -> $$NEW"
	@# Regenerate immediately so the tracked pbxproj changes with project.yml
	@# and one commit carries both (otherwise the next make target regenerates
	@# it after the bump commit and leaves it dirty).
	@$(MAKE) generate

# Options are make variables, not flags: make eats `--dry-run` as its own -n and
# rejects unknown long options, so a flag would never reach the recipe.
publish: ## Cut a release from CHANGELOG [Unreleased] (VERSION=x.y.z DRY_RUN=1 YES=1)
	@VERSION='$(VERSION)' DRY_RUN='$(DRY_RUN)' YES='$(YES)' scripts/publish.sh

clean: ## Remove local build products
	rm -rf build

cache-info: ## Show the persistent Cargo and Xcode cache locations
	@printf 'Cargo:     %s\n' '$(CARGO_TARGET_DIR)'
	@printf 'iOS app:   %s\n' '$(DERIVED)'
	@printf 'HerdenSSH: %s\n' '$(SSH_DERIVED)'
	@printf 'SwiftPM:   %s\n' '$(SOURCE_PACKAGES)'
