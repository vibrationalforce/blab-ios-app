#!/bin/bash

# Build script for Blab iOS App
# This is a simpler alternative to the Makefile

set -e  # Exit on error

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Blab iOS App Builder${NC}"
echo ""

# Check if xcodegen is installed
if ! command -v xcodegen &> /dev/null; then
    echo -e "${RED}❌ xcodegen not found${NC}"
    echo -e "${YELLOW}Installing xcodegen...${NC}"

    if ! command -v brew &> /dev/null; then
        echo -e "${RED}❌ Homebrew not found. Please install Homebrew first:${NC}"
        echo ""
        echo "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi

    brew install xcodegen
fi

# Generate Xcode project
echo -e "${GREEN}📦 Generating Xcode project...${NC}"
xcodegen generate

if [ ! -f "Blab.xcodeproj/project.pbxproj" ]; then
    echo -e "${RED}❌ Failed to generate Xcode project${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Project generated: Blab.xcodeproj${NC}"
echo ""

# Build the app
echo -e "${GREEN}🔨 Building Blab...${NC}"
xcodebuild \
    -project Blab.xcodeproj \
    -scheme Blab \
    -sdk iphoneos \
    -configuration Debug \
    build \
    2>&1 | xcpretty || xcodebuild \
    -project Blab.xcodeproj \
    -scheme Blab \
    -sdk iphoneos \
    -configuration Debug \
    build

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Build successful!${NC}"
    echo ""

    # Check for connected iPhone
    if command -v idevice_id &> /dev/null; then
        DEVICE_ID=$(idevice_id -l | head -n 1)

        if [ -n "$DEVICE_ID" ]; then
            echo -e "${GREEN}📱 iPhone detected: $DEVICE_ID${NC}"
            echo -e "${YELLOW}Run 'make install' to install the app on your iPhone${NC}"
        else
            echo -e "${YELLOW}💡 No iPhone detected. To install:${NC}"
            echo "  1. Connect your iPhone via USB"
            echo "  2. Unlock and trust this computer"
            echo "  3. Run: make install"
        fi
    fi
else
    echo ""
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi
