# Task runner for Herden. Typical flows:
#   make install                 # build Debug and run it on the connected iPhone
#   make bump && make testflight # interim TestFlight build, no version cut
#   make publish                 # cut a release: see docs/guides/releasing.md

PROJECT := Herden.xcodeproj
SCHEME  := Herden
ARCHIVE := build/Herden.xcarchive
DERIVED := build/DerivedData
APP_ID  := com.3loc.herden
SIM     ?= iPhone 17
IOS_WATCH_DEBOUNCE ?= 1s

# First physical device paired with devicectl; override with `make install DEVICE=<uuid>`.
DEVICE ?= $(shell xcrun devicectl list devices 2>/dev/null | awk '/physical[a-z]* *$$/ { for (i = 1; i <= NF; i++) if ($$i ~ /^[0-9A-Fa-f-]{36}$$/) { print $$i; exit } }')

.PHONY: help generate build test install watch-ios-device sim archive upload testflight bump publish clean check-device ssh-artifacts verify-ssh-artifacts

help: ## Show available targets
	@awk -F':.*## ' '/^[a-z-]+:.*## / { printf "  make %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: host-install host-check

host-install: ## Build and install the native Host on this Linux or macOS machine
	sh scripts/install-host-source.sh

host-check: ## Check Host source-build prerequisites without installing anything
	sh scripts/install-host-source.sh --check

ssh-artifacts: ## Rebuild the pinned HerdenSSH XCFrameworks
	Packages/HerdenSSH/Scripts/build-native.sh

verify-ssh-artifacts: ## Verify HerdenSSH artifact hashes, slices, and policy
	Packages/HerdenSSH/Scripts/verify-native.sh

generate: ## Regenerate the Xcode project from project.yml (XcodeGen)
	xcodegen generate

build: ## Build Debug for a physical device without installing
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'generic/platform=iOS' -derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates build

test: ## Run the app and HerdenSSH unit test suites on a simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=iPhone 17' test
	scripts/run-herdenssh-package-tests.sh 'platform=iOS Simulator,name=iPhone 17'

check-device:
	@test -n "$(DEVICE)" || { echo "No physical device found; pass DEVICE=<devicectl uuid>"; exit 1; }

install: check-device build ## Build Debug, install on the iPhone, and relaunch it
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

sim: ## Build Debug and run it on the simulator (override with SIM=<name>)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath $(DERIVED) build
	xcrun simctl boot '$(SIM)' 2>/dev/null || true
	open -a Simulator
	xcrun simctl install booted $(DERIVED)/Build/Products/Debug-iphonesimulator/Herden.app
	xcrun simctl launch --terminate-running-process booted $(APP_ID)

archive: ## Archive a Release build for distribution
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' -archivePath $(ARCHIVE) \
		-allowProvisioningUpdates archive

upload: ## Upload the existing archive to App Store Connect (TestFlight)
	xcodebuild -exportArchive -archivePath $(ARCHIVE) \
		-exportOptionsPlist scripts/ExportOptions.plist \
		-exportPath build/export -allowProvisioningUpdates

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
