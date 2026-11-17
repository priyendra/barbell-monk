SIMULATOR ?= iPhone 18 Pro
# Launch arguments, e.g. `make run ARGS=-sampleData` to skip Apple Health.
ARGS ?=
DESTINATION = platform=iOS Simulator,name=$(SIMULATOR)

.PHONY: project test build run clean

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

clean:
	rm -rf build BarbellMonk.xcodeproj Engine/.build
