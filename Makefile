.PHONY: dev build run reset-permissions clean help

# Variables
BUILD_DIR = /Users/abram/Library/Developer/Xcode/DerivedData/Maccy-debqnufzesstjlbcpoxnsddgiljm/Build/Products/Debug
APP_PATH = $(BUILD_DIR)/Maccy.app
BUNDLE_ID = org.p0deje.Maccy

help:
	@echo "Maccy Development Commands:"
	@echo "  make dev                - Build, reset permissions, and launch (recommended)"
	@echo "  make build              - Build the Debug version only"
	@echo "  make run                - Kill existing Maccy and launch Debug version"
	@echo "  make reset-permissions  - Reset accessibility permissions and relaunch"
	@echo "  make clean              - Kill running Maccy instances"

dev: clean build
	@echo "Resetting accessibility permissions..."
	@tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null || true
	@sleep 1
	@echo "Launching Maccy (will prompt for accessibility)..."
	@open $(APP_PATH)
	@echo "✓ Done! Grant accessibility permissions when prompted."

build:
	@echo "Building Maccy (Debug)..."
	xcodebuild -scheme Maccy -configuration Debug \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

run: clean
	@echo "Launching Maccy..."
	@sleep 1
	@open $(APP_PATH)
	@echo "Maccy launched successfully"

reset-permissions: clean
	@echo "Resetting accessibility permissions..."
	@tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null || true
	@sleep 1
	@echo "Launching Maccy (will prompt for accessibility)..."
	@open $(APP_PATH)
	@echo "Done! Grant accessibility permissions when prompted."

clean:
	@echo "Stopping Maccy..."
	@killall Maccy 2>/dev/null || true
	@sleep 0.5
