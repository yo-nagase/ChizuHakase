#!/bin/bash
# Verifies the CLAUDE.md §1 constraints against the built binary and the source,
# not against anyone's memory of what was added.
#
#   ./tools/check_kids_compliance.sh path/to/WakuwakuChizu.app
#
# These are the App Store Kids category (Guideline 1.3 / 5.1.4) conditions. A
# failure here is a release blocker, not a warning.
set -uo pipefail

APP="${1:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/WakuwakuChizu"
fails=0

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fails=$((fails + 1)); }

echo "Kids category compliance (CLAUDE.md §1)"
echo

# --- Source-level: no forbidden dependencies ------------------------------
echo "dependencies"
if grep -rqE '^\s*(import|@import)\s+(GoogleMobileAds|FirebaseAnalytics|Firebase|Amplitude|Mixpanel|AppsFlyer|Adjust|Branch|FBSDK)' "$SRC" 2>/dev/null; then
    fail "an ad or analytics SDK is imported"
else
    pass "no ad or analytics SDK imported"
fi

if grep -rqE 'import\s+AdSupport|ASIdentifierManager|advertisingIdentifier|AppTrackingTransparency' "$SRC" 2>/dev/null; then
    fail "IDFA / tracking API referenced in source"
else
    pass "no IDFA or tracking API in source"
fi

# Swift Package dependencies would show up in project.yml.
if grep -qE '^\s*packages:' "$ROOT/project.yml" 2>/dev/null; then
    fail "project.yml declares external packages — review each one"
else
    pass "no external package dependencies"
fi

# --- Source-level: no outbound networking ---------------------------------
echo
echo "networking"
# The app must not open sockets or fetch URLs. It has no purchases and no
# outbound links at all, so there is nothing here that legitimately needs the
# network.
hits=$(grep -rnE 'URLSession|URLRequest|NSURLConnection|CFStream|Network\.framework|import\s+Network|WKWebView|SFSafariViewController' "$SRC" 2>/dev/null || true)
if [ -n "$hits" ]; then
    fail "outbound networking API referenced:"
    echo "$hits" | sed 's/^/         /'
else
    pass "no networking API referenced"
fi

if grep -rq 'requiresOnDeviceRecognition = true' "$SRC" 2>/dev/null; then
    pass "speech recognition pinned to on-device"
else
    fail "speech recognition is not pinned to on-device"
fi

# --- Binary-level -----------------------------------------------------------
echo
echo "binary"
if [ -z "$APP" ]; then
    echo "  (skipped: pass a built .app to check the linked binary)"
else
    BIN="$APP/$(basename "$APP" .app)"
    if [ ! -f "$BIN" ]; then
        fail "no executable at $BIN"
    else
        libs=$(otool -L "$BIN" 2>/dev/null)
        if echo "$libs" | grep -qE 'AdSupport|AppTrackingTransparency'; then
            fail "binary links AdSupport or AppTrackingTransparency"
        else
            pass "binary links neither AdSupport nor AppTrackingTransparency"
        fi

        if nm -u "$BIN" 2>/dev/null | grep -q 'ASIdentifierManager'; then
            fail "binary imports ASIdentifierManager"
        else
            pass "ASIdentifierManager absent from the binary"
        fi

        # A Debug bundle that has been through `xcodebuild test` carries Apple's
        # XCTest payload. That is an artefact of the test run, not a shipped
        # dependency, so it is reported and skipped rather than failed.
        frameworks="$APP/Frameworks"
        if [ -d "$frameworks" ]; then
            injected=$(ls "$frameworks" 2>/dev/null \
                | grep -E '^(XCTest|XCTAutomation|XCUIAutomation|XCUnit|Testing|libXCTest)' || true)
            others=$(ls "$frameworks" 2>/dev/null \
                | grep -vE '^(XCTest|XCTAutomation|XCUIAutomation|XCUnit|Testing|libXCTest)' || true)
            if [ -n "$others" ]; then
                fail "third-party frameworks bundled: $(echo "$others" | tr '\n' ' ')"
            else
                pass "no third-party frameworks bundled"
            fi
            if [ -n "$injected" ]; then
                echo "       note: XCTest payload present — this bundle has been"
                echo "             through a test run. Check Release before shipping."
            fi
        else
            pass "no third-party frameworks bundled"
        fi
    fi
fi

echo
if [ "$fails" -eq 0 ]; then
    printf '\033[32mAll checks passed.\033[0m\n'
else
    printf '\033[31m%d check(s) failed.\033[0m\n' "$fails"
fi
exit "$fails"
