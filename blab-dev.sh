#!/bin/bash

# 🌊 BLAB Development Helper Script
# Shortcuts für häufige Entwicklungs-Tasks

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "${BLUE}🌊 BLAB Dev Tool${NC}"
    echo -e "${BLUE}===============${NC}\n"
}

function show_help() {
    print_header
    echo "Usage: ./blab-dev.sh [command]"
    echo ""
    echo "Commands:"
    echo "  build              Build the project"
    echo "  test               Run all tests"
    echo "  test-audio         Run audio tests only"
    echo "  test-visual        Run visual tests only"
    echo "  clean              Clean build artifacts"
    echo "  format             Format code (requires SwiftFormat)"
    echo "  lint               Run SwiftLint"
    echo "  todo               Show all TODOs in code"
    echo "  status             Show git status + metrics"
    echo "  feature <name>     Create new feature branch"
    echo "  commit             Interactive commit with template"
    echo "  metrics            Show code metrics"
    echo ""
}

function build_project() {
    echo -e "${YELLOW}🔨 Building BLAB...${NC}"
    swift build
    echo -e "${GREEN}✅ Build successful${NC}"
}

function run_tests() {
    echo -e "${YELLOW}🧪 Running all tests...${NC}"
    swift test
    echo -e "${GREEN}✅ Tests passed${NC}"
}

function run_audio_tests() {
    echo -e "${YELLOW}🎵 Running audio tests...${NC}"
    swift test --filter BlabTests.Audio
    echo -e "${GREEN}✅ Audio tests passed${NC}"
}

function run_visual_tests() {
    echo -e "${YELLOW}🎨 Running visual tests...${NC}"
    swift test --filter BlabTests.Visual
    echo -e "${GREEN}✅ Visual tests passed${NC}"
}

function clean_build() {
    echo -e "${YELLOW}🧹 Cleaning build artifacts...${NC}"
    swift package clean
    rm -rf .build
    echo -e "${GREEN}✅ Clean complete${NC}"
}

function show_todos() {
    echo -e "${YELLOW}📝 TODOs in codebase:${NC}\n"
    grep -rn "TODO\|FIXME\|HACK" Sources/ || echo "No TODOs found!"
}

function show_status() {
    print_header
    echo -e "${YELLOW}📊 Git Status:${NC}"
    git status -sb
    echo ""
    
    echo -e "${YELLOW}📈 Recent Commits:${NC}"
    git log --oneline -5
    echo ""
    
    echo -e "${YELLOW}📏 Code Metrics:${NC}"
    echo "Swift files: $(find Sources/ -name '*.swift' | wc -l)"
    echo "Lines of code: $(find Sources/ -name '*.swift' | xargs wc -l | tail -1)"
    echo "Test files: $(find Tests/ -name '*.swift' | wc -l)"
}

function create_feature_branch() {
    if [ -z "$1" ]; then
        echo -e "${YELLOW}Usage: ./blab-dev.sh feature <feature-name>${NC}"
        exit 1
    fi
    
    BRANCH_NAME="feature/$1"
    echo -e "${YELLOW}🌿 Creating feature branch: ${BRANCH_NAME}${NC}"
    git checkout -b "$BRANCH_NAME"
    echo -e "${GREEN}✅ Branch created. Happy coding!${NC}"
}

function interactive_commit() {
    echo -e "${YELLOW}📝 Interactive Commit${NC}\n"
    
    # Show status
    git status
    
    # Ask for commit type
    echo ""
    echo "Select commit type:"
    echo "1) feat     - New feature"
    echo "2) fix      - Bug fix"
    echo "3) docs     - Documentation"
    echo "4) refactor - Code refactoring"
    echo "5) test     - Tests"
    echo "6) perf     - Performance"
    read -p "Enter number: " type_num
    
    case $type_num in
        1) TYPE="feat";;
        2) TYPE="fix";;
        3) TYPE="docs";;
        4) TYPE="refactor";;
        5) TYPE="test";;
        6) TYPE="perf";;
        *) TYPE="feat";;
    esac
    
    # Ask for subject
    read -p "Commit subject: " SUBJECT
    
    # Ask for body
    echo "Commit body (enter empty line to finish):"
    BODY=""
    while IFS= read -r line; do
        [ -z "$line" ] && break
        BODY="${BODY}${line}\n"
    done
    
    # Create commit message
    MSG="${TYPE}: ${SUBJECT}\n\n${BODY}\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n\nCo-Authored-By: Claude <noreply@anthropic.com>"
    
    # Stage all changes
    git add .
    
    # Commit
    echo -e "$MSG" | git commit -F -
    
    echo -e "${GREEN}✅ Committed successfully${NC}"
}

function show_metrics() {
    print_header
    echo -e "${YELLOW}📊 Code Metrics:${NC}\n"
    
    echo "=== File Counts ==="
    echo "Swift files: $(find Sources/ -name '*.swift' | wc -l)"
    echo "Test files: $(find Tests/ -name '*.swift' | wc -l)"
    echo "Total files: $(find Sources/ Tests/ -name '*.swift' | wc -l)"
    echo ""
    
    echo "=== Lines of Code ==="
    echo "Source code:"
    find Sources/ -name '*.swift' | xargs wc -l | tail -1
    echo "Test code:"
    find Tests/ -name '*.swift' | xargs wc -l | tail -1
    echo ""
    
    echo "=== Directory Structure ==="
    tree -L 2 Sources/ 2>/dev/null || find Sources/ -type d
}

# Main command router
case "$1" in
    build)
        build_project
        ;;
    test)
        run_tests
        ;;
    test-audio)
        run_audio_tests
        ;;
    test-visual)
        run_visual_tests
        ;;
    clean)
        clean_build
        ;;
    todo)
        show_todos
        ;;
    status)
        show_status
        ;;
    feature)
        create_feature_branch "$2"
        ;;
    commit)
        interactive_commit
        ;;
    metrics)
        show_metrics
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo -e "${YELLOW}Unknown command: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
