#!/bin/bash

# BLAB Debug Build Script
# Kompiliert das Projekt mit ausführlichem Debug-Output

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  BLAB - Debug Build${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Step 1: Check Swift version
echo -e "${YELLOW}→ Checking Swift version...${NC}"
swift --version
echo ""

# Step 2: Check iOS SDK
echo -e "${YELLOW}→ Checking available iOS SDKs...${NC}"
xcodebuild -showsdks | grep iOS || echo "⚠️  No iOS SDKs found (Xcode required)"
echo ""

# Step 3: Resolve Swift Packages
echo -e "${YELLOW}→ Resolving Swift Package dependencies...${NC}"
swift package resolve
echo -e "${GREEN}✓ Dependencies resolved${NC}"
echo ""

# Step 4: Clean build artifacts
echo -e "${YELLOW}→ Cleaning build artifacts...${NC}"
swift package clean
rm -rf .build
echo -e "${GREEN}✓ Build artifacts cleaned${NC}"
echo ""

# Step 5: Build in debug mode
echo -e "${YELLOW}→ Building in debug mode...${NC}"
swift build -c debug --verbose 2>&1 | tee build-debug.log

# Check build result
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✓ Debug build successful!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Build log saved to: ${BLUE}build-debug.log${NC}"
    echo ""
    echo -e "${YELLOW}Note:${NC} Swift Package Manager builds libraries, not iOS apps."
    echo -e "       For iOS app deployment, use Xcode or GitHub Actions."
    exit 0
else
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  ✗ Debug build failed${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Build log saved to: ${BLUE}build-debug.log${NC}"
    echo -e ""
    echo -e "${YELLOW}Common issues:${NC}"
    echo -e "  1. iOS-specific code requires Xcode (AVFoundation, UIKit, etc.)"
    echo -e "  2. Check build-debug.log for detailed error messages"
    echo -e "  3. Ensure all imports are available on macOS for SPM builds"
    echo ""
    exit 1
fi
