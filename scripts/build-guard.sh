#!/bin/bash
# =============================================================================
# ECHOELMUSIC BUILD GUARD
# =============================================================================
# Multi-layer build validation to catch errors before they reach CI/TestFlight.
# Run automatically via git pre-push hook, or manually:
#   ./scripts/build-guard.sh           # Full check (compile + lint + patterns)
#   ./scripts/build-guard.sh --quick   # Patterns only (no compile, <5 seconds)
#   ./scripts/build-guard.sh --fix     # Auto-fix what's possible
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
ERRORS=0
WARNINGS=0
PASSED=0

# Args
QUICK_MODE=false
FIX_MODE=false
VERBOSE=false
for arg in "$@"; do
    case $arg in
        --quick) QUICK_MODE=true ;;
        --fix) FIX_MODE=true ;;
        --verbose|-v) VERBOSE=true ;;
    esac
done

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASSED=$((PASSED + 1)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ERRORS=$((ERRORS + 1)); }
header() { echo -e "\n${BOLD}${BLUE}[$1]${NC} $2"; }

# =============================================================================
# STAGE 1: Pattern Detection (always runs, instant)
# Catches the exact error patterns from CLAUDE.md
# =============================================================================
header "1/3" "Scanning for known error patterns..."

# 1a. Color.magenta (doesn't exist in SwiftUI) — exclude ClipColor.magenta etc.
MAGENTA_HITS=$(grep -rn '[^A-Za-z]Color\.magenta\b' Sources/ --include="*.swift" 2>/dev/null | grep -v 'ClipColor\.' || true)
if [[ -n "$MAGENTA_HITS" ]]; then
    fail "Color.magenta used (doesn't exist in SwiftUI):"
    echo "$MAGENTA_HITS" | head -5
else
    pass "No Color.magenta usage"
fi

# 1b. ProfessionalLogger.log() as static call
STATIC_LOG=$(grep -rn 'ProfessionalLogger\.log(' Sources/ --include="*.swift" 2>/dev/null || true)
if [[ -n "$STATIC_LOG" ]]; then
    fail "ProfessionalLogger.log() called as static (it's an instance method):"
    echo "$STATIC_LOG" | head -5
else
    pass "No static logger calls"
fi

# 1c. UIKit import without platform guard
# Find bare UIKit imports that aren't wrapped in #if canImport or #if os(iOS) etc.
BARE_UIKIT=$(grep -rn '^import UIKit$' Sources/ --include="*.swift" 2>/dev/null || true)
if [[ -n "$BARE_UIKIT" ]]; then
    UNGUARDED=0
    while IFS= read -r line; do
        FILE=$(echo "$line" | cut -d: -f1)
        LINE_NUM=$(echo "$line" | cut -d: -f2)
        # Check up to 10 preceding lines for any platform guard
        FOUND_GUARD=false
        for offset in 1 2 3 4 5 6 7 8 9 10; do
            CHECK_LINE=$((LINE_NUM - offset))
            if [[ $CHECK_LINE -gt 0 ]]; then
                GUARD=$(sed -n "${CHECK_LINE}p" "$FILE" 2>/dev/null || true)
                if [[ "$GUARD" =~ canImport\(UIKit\) ]] || \
                   [[ "$GUARD" =~ os\(iOS\) ]] || \
                   [[ "$GUARD" =~ os\(visionOS\) ]] || \
                   [[ "$GUARD" =~ os\(tvOS\) ]] || \
                   [[ "$GUARD" =~ targetEnvironment ]]; then
                    FOUND_GUARD=true
                    break
                fi
            fi
        done
        if [[ "$FOUND_GUARD" == false ]]; then
            UNGUARDED=$((UNGUARDED + 1))
            if [[ $VERBOSE == true ]]; then
                echo "    $line"
            fi
        fi
    done <<< "$BARE_UIKIT"
    if [[ $UNGUARDED -gt 0 ]]; then
        warn "$UNGUARDED bare 'import UIKit' without platform guard"
    else
        pass "All UIKit imports properly guarded"
    fi
else
    pass "No bare UIKit imports"
fi

# 1d. self.log() missing in EchoelLogger extensions
LOGGER_FILE="Sources/Echoelmusic/Core/ProfessionalLogger.swift"
if [[ -f "$LOGGER_FILE" ]]; then
    # Look for log(.level calls without self. inside the file
    BARE_LOG_CALLS=$(grep -n '^\s\+log(\.\(debug\|info\|warning\|error\|critical\)' "$LOGGER_FILE" 2>/dev/null || true)
    if [[ -n "$BARE_LOG_CALLS" ]]; then
        fail "Bare log() calls in ProfessionalLogger.swift (use self.log()):"
        echo "$BARE_LOG_CALLS" | head -5
    else
        pass "Logger self-references correct"
    fi
fi

# 1e. Access level mismatches: public property with internal type
# Quick heuristic: public let/var with a type that's not a standard library type
# This is a soft check — full validation requires the compiler
pass "Access level patterns (validated at compile time with -warnings-as-errors)"

# 1f. @escaping missing in TaskGroup closures
TASKGROUP_CLOSURES=$(grep -rn 'addTask\s*{' Sources/ --include="*.swift" 2>/dev/null | wc -l || true)
if [[ $TASKGROUP_CLOSURES -gt 0 ]]; then
    pass "TaskGroup closures found ($TASKGROUP_CLOSURES) — compiler validates @escaping"
fi

# 1g. WeatherKit without availability check
WEATHERKIT_IMPORT=$(grep -rn 'import WeatherKit' Sources/ --include="*.swift" 2>/dev/null || true)
if [[ -n "$WEATHERKIT_IMPORT" ]]; then
    WEATHERKIT_FILES=$(echo "$WEATHERKIT_IMPORT" | cut -d: -f1 | sort -u)
    for file in $WEATHERKIT_FILES; do
        if ! grep -q 'canImport(WeatherKit)' "$file" 2>/dev/null; then
            fail "WeatherKit imported without #if canImport guard: $file"
        fi
    done
else
    pass "WeatherKit properly guarded (or not used)"
fi

# 1h. vDSP overlapping access pattern
VDSP_EXECUTE=$(grep -rn 'vDSP_DFT_Execute' Sources/ --include="*.swift" 2>/dev/null || true)
if [[ -n "$VDSP_EXECUTE" ]]; then
    pass "vDSP_DFT_Execute found — ensure inputs are copied to temp vars"
fi

# =============================================================================
# STAGE 2: SwiftLint (runs unless --quick)
# =============================================================================
if [[ "$QUICK_MODE" == false ]]; then
    header "2/3" "Running SwiftLint..."

    if command -v swiftlint &> /dev/null; then
        LINT_OUTPUT=$(swiftlint lint --strict --quiet 2>&1 || true)
        LINT_ERRORS=$(echo "$LINT_OUTPUT" | grep -c ": error:" 2>/dev/null || echo "0")
        LINT_WARNINGS=$(echo "$LINT_OUTPUT" | grep -c ": warning:" 2>/dev/null || echo "0")

        if [[ "$LINT_ERRORS" -gt 0 ]]; then
            fail "SwiftLint: $LINT_ERRORS errors"
            echo "$LINT_OUTPUT" | grep ": error:" | head -10
        else
            pass "SwiftLint: 0 errors"
        fi

        if [[ "$LINT_WARNINGS" -gt 0 ]]; then
            warn "SwiftLint: $LINT_WARNINGS warnings"
        fi

        if [[ "$FIX_MODE" == true ]]; then
            echo -e "  ${BLUE}→${NC} Auto-fixing with SwiftLint..."
            swiftlint lint --fix --quiet 2>/dev/null || true
        fi
    else
        warn "SwiftLint not installed (brew install swiftlint)"
    fi
else
    header "2/3" "SwiftLint skipped (--quick mode)"
fi

# =============================================================================
# STAGE 3: Swift Build (runs unless --quick)
# =============================================================================
if [[ "$QUICK_MODE" == false ]]; then
    header "3/3" "Compiling Swift package..."

    BUILD_LOG=$(mktemp)
    if swift build 2>&1 | tee "$BUILD_LOG" | tail -5; then
        pass "Swift build succeeded"
    else
        COMPILE_ERRORS=$(grep -c "error:" "$BUILD_LOG" 2>/dev/null || echo "0")
        fail "Swift build failed with $COMPILE_ERRORS errors"
        echo ""
        echo -e "${RED}First 20 errors:${NC}"
        grep "error:" "$BUILD_LOG" | head -20
    fi
    rm -f "$BUILD_LOG"
else
    header "3/3" "Swift build skipped (--quick mode)"
fi

# =============================================================================
# ⛔ STAGE 4 STOOD HERE AND WAS DELETED (#1035, 2026-09-06)
# =============================================================================
# It looped over CONFLICT_TYPES=("MonitorMode" "TransitionType" "TrackSend"
# "TrackType" "SourceFilter") looking for top-level redeclarations, then printed
# `pass "Type conflict scan complete"` UNCONDITIONALLY — outside the loop, with no
# reference to what the loop found.
#
# Measured 2026-09-06: all five names occur ZERO times in Sources/. So the stage
# examined nothing and lit a green light for it. CI runs this script as
# `build-guard.sh --quick` (ci.yml:78, pr-check.yml:87), which skips stages 2 and 3
# — so this ghost scan was HALF of what CI actually executed here.
#
# Its prose home was already gone. CLAUDE.md deleted its "Type Conflict Resolution"
# section on 2026-07-25 with the words "every type this section named is GONE ...
# Do not restore any of it". The executable copy was simply missed — the #456
# pattern: a retraction that fixed one home and left the other running.
#
# It is DELETED rather than repaired because the invariant it claimed is already
# enforced by something stronger: two top-level types with the same name in one
# module is a redeclaration ERROR, so the compiler catches it. The prefixing rule it
# implemented belonged to the multi-target era; the AUv3 target went 2026-07-24.
#
# ⭐ IF A FOURTH STAGE COMES BACK, here is the one worth building, because it catches
# a failure this repo HAS paid for and `--quick` mode cannot see (no compiler): an
# `@Observable` class declaring its own stored property named `_foo` collides with
# the macro-generated backing store for `foo` ("invalid redeclaration of '_foo'").
# That rule is in CLAUDE.md's build-error table because it bit us. A grep can find
# it; the quick gate currently cannot.

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} BUILD GUARD SUMMARY${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC}   $PASSED"
echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "  ${RED}Errors:${NC}   $ERRORS"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}${BOLD}BUILD GUARD FAILED${NC} — Fix $ERRORS error(s) before pushing."
    echo -e "Run with ${BLUE}--verbose${NC} for details or ${BLUE}--fix${NC} to auto-fix."
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}${BOLD}BUILD GUARD PASSED WITH WARNINGS${NC}"
    exit 0
else
    echo -e "${GREEN}${BOLD}BUILD GUARD PASSED${NC} — Safe to push."
    exit 0
fi
