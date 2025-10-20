#!/bin/bash
#
# build.sh - VS Code friendly build script for BLAB
# Wraps swift build with better output and error handling
#
# Usage:
#   ./build.sh           # Standard build
#   ./build.sh clean     # Clean build
#   ./build.sh release   # Release build
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  🎵 BLAB - Building from VS Code    ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo -e "${RED}❌ Error: Package.swift not found${NC}"
    echo "Please run this script from the project root directory"
    exit 1
fi

# Handle different build modes
BUILD_MODE="debug"
CLEAN_BUILD=false

case "$1" in
    clean)
        CLEAN_BUILD=true
        echo -e "${YELLOW}🧹 Cleaning build artifacts...${NC}"
        swift package clean
        echo ""
        ;;
    release)
        BUILD_MODE="release"
        echo -e "${YELLOW}🚀 Building in RELEASE mode...${NC}"
        ;;
    *)
        echo -e "${YELLOW}🔨 Building in DEBUG mode...${NC}"
        ;;
esac

echo ""
echo -e "${BLUE}📦 Resolving dependencies...${NC}"
swift package resolve

echo ""
echo -e "${BLUE}🔨 Building BLAB...${NC}"
echo ""

# Build with appropriate configuration
if [ "$BUILD_MODE" = "release" ]; then
    swift build -c release
else
    swift build
fi

# Check if build succeeded
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Build Successful!                ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Build artifacts:${NC}"
    if [ "$BUILD_MODE" = "release" ]; then
        ls -lh .build/release/ 2>/dev/null || echo "  (Release build directory)"
    else
        ls -lh .build/debug/ 2>/dev/null || echo "  (Debug build directory)"
    fi
    echo ""
    echo -e "${YELLOW}📱 Next step: Deploy to iPhone${NC}"
    echo "   Run: ${GREEN}./deploy.sh${NC}"
    echo ""
else
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ❌ Build Failed!                    ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}💡 Tips:${NC}"
    echo "  1. Check the error messages above"
    echo "  2. Make sure all dependencies are installed"
    echo "  3. Try: ${GREEN}./build.sh clean${NC}"
    echo ""
    exit 1
fi
