#!/bin/bash
#
# deploy.sh - Deploy BLAB to iPhone (via Xcode)
# Generates Xcode project and provides deployment instructions
#
# Usage:
#   ./deploy.sh
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Banner
echo -e "${MAGENTA}╔═══════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║  📱 BLAB - Deploy to iPhone         ║${NC}"
echo -e "${MAGENTA}╚═══════════════════════════════════════╝${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo -e "${RED}❌ Error: Package.swift not found${NC}"
    echo "Please run this script from the project root directory"
    exit 1
fi

echo -e "${YELLOW}⚙️  Step 1: Building package first...${NC}"
echo ""
swift build

if [ $? -ne 0 ]; then
    echo ""
    echo -e "${RED}❌ Build failed! Fix errors first.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Build successful!${NC}"
echo ""

echo -e "${YELLOW}⚙️  Step 2: Generating Xcode project...${NC}"
echo ""

# Generate Xcode project
swift package generate-xcodeproj

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Xcode project generated!${NC}"
    echo ""
    
    # Check if Xcode is installed
    if command -v xcodebuild &> /dev/null; then
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║  📱 DEPLOYMENT INSTRUCTIONS                              ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${BLUE}1. Opening Xcode project...${NC}"
        open Blab.xcodeproj
        echo ""
        echo -e "${YELLOW}2. In Xcode, do the following:${NC}"
        echo ""
        echo -e "   ${GREEN}a)${NC} Select the 'Blab' target in the project navigator"
        echo -e "   ${GREEN}b)${NC} Go to 'Signing & Capabilities' tab"
        echo -e "   ${GREEN}c)${NC} Select your Team (Apple ID)"
        echo -e "   ${GREEN}d)${NC} Bundle ID: ${CYAN}com.vibrationalforce.blab${NC}"
        echo ""
        echo -e "   ${GREEN}e)${NC} Connect your iPhone 16 Pro Max via USB"
        echo -e "   ${GREEN}f)${NC} Product → Destination → iPhone 16 Pro Max"
        echo -e "   ${GREEN}g)${NC} Press ${CYAN}Cmd+R${NC} to build and run"
        echo ""
        echo -e "${MAGENTA}3. On your iPhone:${NC}"
        echo ""
        echo -e "   ${GREEN}•${NC} Grant microphone permission when prompted"
        echo -e "   ${GREEN}•${NC} Grant HealthKit permission (optional, for HRV)"
        echo -e "   ${GREEN}•${NC} Grant motion permission (for head tracking)"
        echo ""
        echo -e "${BLUE}4. Once app is running on iPhone:${NC}"
        echo ""
        echo -e "   ${YELLOW}→${NC} Close Xcode"
        echo -e "   ${YELLOW}→${NC} Return to VS Code"
        echo -e "   ${YELLOW}→${NC} Continue developing!"
        echo ""
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║  💡 TIP: You only need to do this once per major update  ║${NC}"
        echo -e "${CYAN}║      95% of development happens in VS Code!              ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
    else
        echo -e "${RED}⚠️  Xcode not found!${NC}"
        echo ""
        echo "Install Xcode from the Mac App Store:"
        echo "  https://apps.apple.com/app/xcode/id497799835"
        echo ""
        echo "After installation, run this script again."
        echo ""
        exit 1
    fi
else
    echo ""
    echo -e "${RED}❌ Failed to generate Xcode project!${NC}"
    echo ""
    echo -e "${YELLOW}💡 Tips:${NC}"
    echo "  1. Make sure Package.swift is valid"
    echo "  2. Try: ${GREEN}swift package clean${NC}"
    echo "  3. Check for Swift Package Manager errors above"
    echo ""
    exit 1
fi
