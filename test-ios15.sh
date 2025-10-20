#!/bin/bash

# BLAB iOS 15 Compatibility Test Script
# Tests the app on iOS 15.0+ simulators (requires Xcode)

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  BLAB - iOS 15 Compatibility Test${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}✗ Xcode not found${NC}"
    echo ""
    echo "This script requires Xcode to run iOS simulator tests."
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  1. Install Xcode from the App Store"
    echo "  2. Use GitHub Actions for automated testing (free!)"
    echo "  3. See: TESTFLIGHT_SETUP.md for TestFlight deployment"
    echo ""
    exit 1
fi

echo -e "${YELLOW}→ Checking Xcode version...${NC}"
xcodebuild -version
echo ""

# Step 1: List available simulators
echo -e "${YELLOW}→ Checking for iOS 15 simulators...${NC}"
xcrun simctl list devices available | grep "iOS 15" || {
    echo -e "${RED}No iOS 15 simulators found${NC}"
    echo ""
    echo -e "${YELLOW}Available simulators:${NC}"
    xcrun simctl list devices available | grep "iPhone"
    echo ""
    echo "You may need to download iOS 15 runtime via Xcode → Preferences → Components"
    exit 1
}
echo ""

# Step 2: Resolve dependencies
echo -e "${YELLOW}→ Resolving Swift Package dependencies...${NC}"
swift package resolve
echo -e "${GREEN}✓ Dependencies resolved${NC}"
echo ""

# Step 3: Build for iOS 15 Simulator
echo -e "${YELLOW}→ Building for iOS 15.0 Simulator...${NC}"
xcodebuild clean build \
    -scheme Blab \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 13,OS=15.0' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    | tee build-ios15.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✓ iOS 15 build successful!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Build log: ${BLUE}build-ios15.log${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  • Run app in Simulator via Xcode"
    echo "  • Test core features (mic, binaural beats, HealthKit)"
    echo "  • Verify graceful fallbacks (spatial audio disabled on iOS 15)"
    echo ""
else
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  ✗ iOS 15 build failed${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Build log: ${BLUE}build-ios15.log${NC}"
    echo ""
    echo -e "${YELLOW}Check the log for compatibility issues.${NC}"
    exit 1
fi

# Step 4: Run unit tests
echo -e "${YELLOW}→ Running unit tests on iOS 15...${NC}"
xcodebuild test \
    -scheme Blab \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 13,OS=15.0' \
    CODE_SIGNING_ALLOWED=NO \
    | tee test-ios15.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✓ iOS 15 tests passed!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Test log: ${BLUE}test-ios15.log${NC}"
    echo ""
else
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  ⚠ Some tests failed${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Test log: ${BLUE}test-ios15.log${NC}"
fi
