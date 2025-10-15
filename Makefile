# Makefile for Blab iOS App
# Makes building and deploying the app easy!

# Variables
PROJECT_NAME = Blab
SCHEME = Blab
CONFIGURATION = Debug
SDK = iphoneos
BUILD_DIR = build
DERIVED_DATA = $(BUILD_DIR)/DerivedData

# Colors for output
GREEN = \033[0;32m
YELLOW = \033[0;33m
NC = \033[0m # No Color

.PHONY: help setup generate clean build install run test

# Default target - show help
help:
	@echo "$(GREEN)Blab iOS App Build Commands:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make setup$(NC)      - Install required tools (xcodegen, ios-deploy)"
	@echo "  $(YELLOW)make generate$(NC)   - Generate Xcode project from project.yml"
	@echo "  $(YELLOW)make build$(NC)      - Build the iOS app"
	@echo "  $(YELLOW)make install$(NC)    - Install app on connected iPhone"
	@echo "  $(YELLOW)make run$(NC)        - Build + Install in one command"
	@echo "  $(YELLOW)make clean$(NC)      - Remove build artifacts"
	@echo "  $(YELLOW)make test$(NC)       - Run unit tests"
	@echo ""

# Install required tools
setup:
	@echo "$(GREEN)Installing required tools...$(NC)"
	@if ! command -v brew &> /dev/null; then \
		echo "$(YELLOW)Homebrew not found. Install it first:$(NC)"; \
		echo "/bin/bash -c \"\$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""; \
		exit 1; \
	fi
	brew install xcodegen
	brew install ios-deploy
	brew install libimobiledevice
	@echo "$(GREEN)Setup complete!$(NC)"

# Generate Xcode project from project.yml
generate:
	@echo "$(GREEN)Generating Xcode project...$(NC)"
	xcodegen generate
	@echo "$(GREEN)Project generated: $(PROJECT_NAME).xcodeproj$(NC)"

# Build the app
build: generate
	@echo "$(GREEN)Building $(PROJECT_NAME)...$(NC)"
	xcodebuild \
		-project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-sdk $(SDK) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA) \
		build
	@echo "$(GREEN)Build complete!$(NC)"

# Install app on connected iPhone
install:
	@echo "$(GREEN)Installing $(PROJECT_NAME) on iPhone...$(NC)"
	@DEVICE_ID=$$(idevice_id -l | head -n 1); \
	if [ -z "$$DEVICE_ID" ]; then \
		echo "$(YELLOW)No iPhone detected. Please:$(NC)"; \
		echo "  1. Connect iPhone via USB"; \
		echo "  2. Unlock iPhone"; \
		echo "  3. Trust this computer"; \
		exit 1; \
	fi; \
	echo "$(GREEN)Found device: $$DEVICE_ID$(NC)"; \
	APP_PATH=$$(find $(DERIVED_DATA) -name "$(PROJECT_NAME).app" | head -n 1); \
	if [ -z "$$APP_PATH" ]; then \
		echo "$(YELLOW)App not found. Run 'make build' first.$(NC)"; \
		exit 1; \
	fi; \
	ios-deploy --id $$DEVICE_ID --bundle "$$APP_PATH"
	@echo "$(GREEN)Installation complete!$(NC)"

# Build and install in one command
run: build install
	@echo "$(GREEN)$(PROJECT_NAME) is now running on your iPhone!$(NC)"

# Clean build artifacts
clean:
	@echo "$(GREEN)Cleaning build artifacts...$(NC)"
	rm -rf $(BUILD_DIR)
	rm -rf $(DERIVED_DATA)
	rm -rf *.xcodeproj
	@echo "$(GREEN)Clean complete!$(NC)"

# Run tests
test: generate
	@echo "$(GREEN)Running tests...$(NC)"
	xcodebuild test \
		-project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-sdk iphonesimulator \
		-destination 'platform=iOS Simulator,name=iPhone 14 Pro'
	@echo "$(GREEN)Tests complete!$(NC)"
