#!/bin/bash
# =============================================================================
# ECHOELMUSIC - PRE-FLIGHT VALIDATION SCRIPT
# =============================================================================
# Run this before TestFlight deployment to catch issues early
# Usage: ./scripts/preflight-check.sh [--fix]
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0
PASSED=0

# Args
FIX_MODE=false
if [[ "$1" == "--fix" ]]; then
    FIX_MODE=true
fi

echo ""
echo "=============================================="
echo "  ECHOELMUSIC PRE-FLIGHT VALIDATION"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASSED=$((PASSED + 1))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ERRORS=$((ERRORS + 1))
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# -----------------------------------------------------------------------------
# 1. Check required files exist
# -----------------------------------------------------------------------------
echo "--- Checking Required Files ---"

REQUIRED_FILES=(
    "Package.swift"
    "project.yml"
    "fastlane/Fastfile"
    "fastlane/Appfile"
    "Resources/PrivacyInfo.xcprivacy"
    "Resources/iOS/Info.plist"
    "Echoelmusic.entitlements"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        pass "$file exists"
    else
        fail "$file is missing"
    fi
done

# -----------------------------------------------------------------------------
# 2. Check Bundle IDs are consistent
# -----------------------------------------------------------------------------
echo ""
echo "--- Checking Bundle ID Consistency ---"

EXPECTED_BUNDLE_ID="com.echoelmusic.app"

# Check project.yml
if grep -q "PRODUCT_BUNDLE_IDENTIFIER: $EXPECTED_BUNDLE_ID" project.yml 2>/dev/null; then
    pass "Bundle ID in project.yml: $EXPECTED_BUNDLE_ID"
else
    fail "Bundle ID mismatch in project.yml"
fi

# Check Fastfile
if grep -q "app_identifier: \"$EXPECTED_BUNDLE_ID\"" fastlane/Fastfile 2>/dev/null || \
   grep -q "$EXPECTED_BUNDLE_ID" fastlane/Fastfile 2>/dev/null; then
    pass "Bundle ID in Fastfile matches"
else
    fail "Bundle ID mismatch in Fastfile"
fi

# Check Appfile
if grep -q "$EXPECTED_BUNDLE_ID" fastlane/Appfile 2>/dev/null; then
    pass "Bundle ID in Appfile matches"
else
    fail "Bundle ID mismatch in Appfile"
fi

# -----------------------------------------------------------------------------
# 3. Check Swift Package builds
# -----------------------------------------------------------------------------
echo ""
echo "--- Checking Swift Package ---"

# ⛔ This block ran `swift package describe` unconditionally and called a non-zero
# exit "Swift package has errors". On any machine WITHOUT a toolchain — every web
# session, and this container — that is a FAIL for a package that is perfectly fine.
# An absent tool is a WARN, never a FAIL; the XcodeGen and Fastlane sections two
# blocks down already got this right, so the file contradicted itself.
if ! command -v swift &> /dev/null; then
    warn "Swift toolchain not installed — package validity UNMEASURED here (run on the Mac)"
else
    if swift package describe > /dev/null 2>&1; then
        pass "Swift package is valid"
    else
        fail "Swift package has errors"
    fi

    # Quick syntax check
    if swift build --skip-build 2>/dev/null || swift package dump-package > /dev/null 2>&1; then
        pass "Package.swift syntax is valid"
    else
        warn "Could not validate Package.swift syntax (may need full build)"
    fi
fi

# -----------------------------------------------------------------------------
# 4. Check XcodeGen can generate project
# -----------------------------------------------------------------------------
echo ""
echo "--- Checking XcodeGen ---"

if command -v xcodegen &> /dev/null; then
    pass "XcodeGen is installed"

    # Validate project.yml syntax
    if xcodegen dump --spec project.yml > /dev/null 2>&1; then
        pass "project.yml syntax is valid"
    else
        fail "project.yml has syntax errors"
    fi
else
    warn "XcodeGen not installed (install with: brew install xcodegen)"
fi

# -----------------------------------------------------------------------------
# 5. Check Fastlane configuration
# -----------------------------------------------------------------------------
echo ""
echo "--- Checking Fastlane ---"

if command -v fastlane &> /dev/null; then
    pass "Fastlane is installed"
else
    warn "Fastlane not installed (install with: gem install fastlane)"
fi

# Check for the lanes the DEPLOY PATH actually calls.
# ⛔ This list said ("beta" "beta_watchos" "beta_tvos" "beta_visionos") and NONE of
# those four lanes has ever existed in this Fastfile — the real names are
# `setup_signing` / `upload` / `upload_watchos` / `upload_tvos` / `upload_visionos`.
# Nobody noticed because the counter bug above killed the script long before this
# section ran: four permanent phantom FAILs behind an instrument that never spoke.
# `setup_signing` is named literally by testflight.yml (`fastlane ios setup_signing`),
# so a rename there breaks the deploy — that is what makes it worth gating on.
REQUIRED_LANES=("setup_signing" "upload")
for lane in "${REQUIRED_LANES[@]}"; do
    if grep -q "lane :$lane" fastlane/Fastfile 2>/dev/null; then
        pass "Lane '$lane' exists in Fastfile"
    else
        fail "Lane '$lane' missing from Fastfile"
    fi
done

# -----------------------------------------------------------------------------
# 6. Check App Store Metadata
# -----------------------------------------------------------------------------
echo ""
echo "--- Checking App Store Metadata ---"

METADATA_DIR="fastlane/metadata/en-US"
REQUIRED_METADATA=(
    "description.txt"
    "keywords.txt"
    "release_notes.txt"
    "privacy_url.txt"
    "support_url.txt"
)

for meta in "${REQUIRED_METADATA[@]}"; do
    if [[ -f "$METADATA_DIR/$meta" ]]; then
        # Check if file has content
        if [[ -s "$METADATA_DIR/$meta" ]]; then
            pass "$meta exists and has content"
        else
            fail "$meta is empty"
        fi
    else
        fail "$meta is missing"
    fi
done

# Check description length (4000 char limit)
if [[ -f "$METADATA_DIR/description.txt" ]]; then
    DESC_LENGTH=$(wc -c < "$METADATA_DIR/description.txt" | tr -d ' ')
    if [[ $DESC_LENGTH -le 4000 ]]; then
        pass "Description length: $DESC_LENGTH/4000 chars"
    else
        fail "Description too long: $DESC_LENGTH/4000 chars"
    fi
fi

# Check keywords (100 char limit)
if [[ -f "$METADATA_DIR/keywords.txt" ]]; then
    KW_LENGTH=$(wc -c < "$METADATA_DIR/keywords.txt" | tr -d ' ')
    if [[ $KW_LENGTH -le 100 ]]; then
        pass "Keywords length: $KW_LENGTH/100 chars"
    else
        fail "Keywords too long: $KW_LENGTH/100 chars"
    fi
fi

# -----------------------------------------------------------------------------
# 7. Check Privacy Manifest
# -----------------------------------------------------------------------------
echo ""
echo "--- Checking Privacy Manifest ---"

PRIVACY_FILE="Resources/PrivacyInfo.xcprivacy"
if [[ -f "$PRIVACY_FILE" ]]; then
    # Check for required keys
    if grep -q "NSPrivacyTracking" "$PRIVACY_FILE"; then
        pass "Privacy tracking declaration present"
    else
        warn "NSPrivacyTracking key missing in privacy manifest"
    fi

    if grep -q "NSPrivacyCollectedDataTypes" "$PRIVACY_FILE"; then
        pass "Data collection declaration present"
    else
        warn "NSPrivacyCollectedDataTypes missing in privacy manifest"
    fi
fi

# -----------------------------------------------------------------------------
# 8. Check Info.plist for required keys
# -----------------------------------------------------------------------------
echo ""
echo "--- Checking Info.plist ---"

PLIST_FILE="Resources/iOS/Info.plist"
if [[ -f "$PLIST_FILE" ]]; then
    # HealthKit usage descriptions (required for App Store)
    REQUIRED_KEYS=(
        "NSHealthShareUsageDescription"
        "NSHealthUpdateUsageDescription"
        "NSMicrophoneUsageDescription"
    )

    for key in "${REQUIRED_KEYS[@]}"; do
        if grep -q "$key" "$PLIST_FILE"; then
            pass "$key present in Info.plist"
        else
            fail "$key missing from Info.plist"
        fi
    done
fi

# -----------------------------------------------------------------------------
# 9. Check for secrets/sensitive data
# -----------------------------------------------------------------------------
echo ""
echo "--- Security Check ---"

# Check for potential secrets in code
SENSITIVE_PATTERNS=(
    "PRIVATE_KEY"
    "api_key.*=.*['\"][a-zA-Z0-9]"
    "password.*=.*['\"]"
    "secret.*=.*['\"]"
)

FOUND_SECRETS=false
for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    # Exclude common false positives
    MATCHES=$(grep -r -i "$pattern" Sources/ --include="*.swift" 2>/dev/null | grep -v "// " | grep -v "ENV\[" | grep -v "secrets\." | head -5 || true)
    if [[ -n "$MATCHES" ]]; then
        FOUND_SECRETS=true
        warn "Potential sensitive data found (review manually):"
        echo "$MATCHES" | head -3
    fi
done

if [[ "$FOUND_SECRETS" == "false" ]]; then
    pass "No obvious secrets found in source code"
fi

# Check .gitignore for sensitive files
if grep -q "\.env" .gitignore 2>/dev/null; then
    pass ".env files are gitignored"
else
    warn ".env files should be in .gitignore"
fi

# -----------------------------------------------------------------------------
# 10. Check GitHub Actions workflow
# -----------------------------------------------------------------------------
echo ""
echo "--- Checking CI/CD Workflow ---"

WORKFLOW_FILE=".github/workflows/testflight.yml"
if [[ -f "$WORKFLOW_FILE" ]]; then
    pass "TestFlight workflow exists"

    # Check for required secrets references
    REQUIRED_SECRETS=(
        "APP_STORE_CONNECT_KEY_ID"
        "APP_STORE_CONNECT_ISSUER_ID"
        "APP_STORE_CONNECT_PRIVATE_KEY"
        "APPLE_TEAM_ID"
    )

    for secret in "${REQUIRED_SECRETS[@]}"; do
        if grep -q "secrets.$secret" "$WORKFLOW_FILE"; then
            pass "Secret reference: $secret"
        else
            fail "Missing secret reference: $secret"
        fi
    done
else
    fail "TestFlight workflow missing"
fi

# -----------------------------------------------------------------------------
# 11. Check version numbers
# -----------------------------------------------------------------------------
echo ""
echo "--- Checking Version Numbers ---"

if [[ -f "project.yml" ]]; then
    VERSION=$(grep "MARKETING_VERSION:" project.yml | head -1 | sed 's/.*: *//' | tr -d '"')
    if [[ -n "$VERSION" ]]; then
        pass "Marketing version: $VERSION"

        # Validate semver format
        if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            pass "Version follows semver format"
        else
            warn "Version '$VERSION' doesn't follow strict semver (x.y.z)"
        fi
    else
        fail "MARKETING_VERSION not found in project.yml"
    fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  PRE-FLIGHT SUMMARY"
echo "=============================================="
echo ""
echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Errors:${NC}   $ERRORS"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}PRE-FLIGHT CHECK FAILED${NC}"
    echo "Fix the errors above before deploying to TestFlight."
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}PRE-FLIGHT CHECK PASSED WITH WARNINGS${NC}"
    echo "Review warnings above. Deployment can proceed."
    exit 0
else
    echo -e "${GREEN}PRE-FLIGHT CHECK PASSED${NC}"
    echo "Ready for TestFlight deployment!"
    exit 0
fi
