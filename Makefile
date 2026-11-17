SIMULATOR ?= iPhone 18 Pro
# Launch arguments, e.g. `make run ARGS=-sampleData` to skip Apple Health.
ARGS ?=
DESTINATION = platform=iOS Simulator,name=$(SIMULATOR)

.PHONY: project test build run archive upload clean

# Regenerate BarbellMonk.xcodeproj from project.yml.
project:
	xcodegen generate --quiet

# Engine unit tests; run on the Mac, no simulator needed.
test:
	cd Engine && swift test

# Build the dev app for the simulator.
build: project
	xcodebuild -project BarbellMonk.xcodeproj -scheme BarbellMonk \
		-configuration Debug -destination '$(DESTINATION)' \
		-derivedDataPath build -quiet build

# Build, install and launch the dev app in the simulator.
run: build
	xcrun simctl boot '$(SIMULATOR)' 2>/dev/null || true
	-open "$$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null
	xcrun simctl install '$(SIMULATOR)' build/Build/Products/Debug-iphonesimulator/BarbellMonk.app
	xcrun simctl launch --terminate-running-process '$(SIMULATOR)' com.priyendra.barbellmonk.dev $(ARGS)

# Every upload needs a higher build number than the last.
BUILD_NUMBER := $(shell date +%Y%m%d%H%M)

# Signed release build of "barbellmonk". The first run registers the app ID
# with Apple.
archive: project
	xcodebuild -project BarbellMonk.xcodeproj -scheme BarbellMonk \
		-configuration Release -destination 'generic/platform=iOS' \
		-archivePath build/BarbellMonk.xcarchive -allowProvisioningUpdates \
		CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) -quiet archive

# Upload a fresh archive to App Store Connect; it shows up in TestFlight
# after Apple finishes processing it.
upload: archive
	xcodebuild -exportArchive -archivePath build/BarbellMonk.xcarchive \
		-exportOptionsPlist ExportOptions.plist -exportPath build/export \
		-allowProvisioningUpdates

clean:
	rm -rf build BarbellMonk.xcodeproj Engine/.build
