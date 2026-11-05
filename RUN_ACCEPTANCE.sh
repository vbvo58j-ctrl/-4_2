#!/usr/bin/env bash
# One-command acceptance test. Never deletes existing app data or .env files.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 2
pass=0; fail=0; skip=0
run_step() {
    local label="$1"; shift
    printf '\n===== %s =====\n' "$label"
    if "$@"; then echo "PASS: $label"; pass=$((pass + 1)); else echo "FAIL: $label"; fail=$((fail + 1)); fi
}
run_step "STATIC_SOURCE_AND_RESOURCES" python3 scripts/check_static.py
run_step "V26_SOURCE_CONTRACTS" python3 scripts/check_v26_contracts.py
run_step "PRODUCTION_SECURITY_GATE" python3 scripts/check_production_security.py
if command -v flutter >/dev/null 2>&1; then
    run_step "FLUTTER_PUB_GET" flutter pub get
    if [ "$fail" -eq 0 ]; then
        run_step "FLUTTER_ANALYZE" flutter analyze
        run_step "FLUTTER_TEST" flutter test
        run_step "FLUTTER_BUILD_APK_DEBUG" flutter build apk --debug
    else
        skip=$((skip + 3))
        echo "SKIP: Flutter analyze/test/build because a prerequisite failed"
    fi
else
    echo "FAIL: Flutter SDK was not found in PATH; cannot verify the Android build"
    fail=$((fail + 1)); skip=$((skip + 4))
fi
printf '\n========== ACCEPTANCE SUMMARY ==========\nPASS=%s FAIL=%s SKIPPED=%s\n' "$pass" "$fail" "$skip"
if [ "$fail" -gt 0 ]; then
    echo 'The build is NOT verified. Read the failing lines above.'
    if [ -t 0 ]; then read -r -p 'اضغط Enter لإغلاق الفحص... ' _ || true; fi
    exit 1
fi
echo 'All available checks passed.'
