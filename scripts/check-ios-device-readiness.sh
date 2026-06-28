#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_FILE="${PROJECT_ROOT}/DailyLang.xcodeproj"
readonly PBXPROJ_FILE="${PROJECT_FILE}/project.pbxproj"

print_section() {
  printf '\n== %s ==\n' "$1"
}

print_section "Xcode"
if xcode_path="$(xcode-select -p 2>/dev/null)"; then
  printf 'Developer dir: %s\n' "${xcode_path}"
else
  printf 'Xcode developer dir is not configured.\n'
fi

print_section "Connected devices"
if xcrun xctrace list devices; then
  printf '\nIf only the Mac appears under Devices, connect and unlock the iPhone, then tap Trust This Computer.\n'
else
  printf 'Could not read Xcode devices. Open Xcode once, then rerun this script.\n'
fi

print_section "Code signing identities"
if identities="$(security find-identity -v -p codesigning 2>/dev/null)"; then
  printf '%s\n' "${identities}"
  if printf '%s\n' "${identities}" | grep -q "0 valid identities found"; then
    printf '\nCreate an Apple Development certificate in Xcode > Settings > Accounts > Manage Certificates.\n'
  fi
else
  printf 'Could not read code signing identities from Keychain.\n'
fi

print_section "DailyLang signing settings"
if [[ -f "${PBXPROJ_FILE}" ]]; then
  grep -nE "CODE_SIGN_STYLE|DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER" "${PBXPROJ_FILE}" || true
  if grep -q 'DEVELOPMENT_TEAM = "";' "${PBXPROJ_FILE}"; then
    printf '\nDailyLang has no Team selected yet. Set it in Target DailyLang > Signing & Capabilities.\n'
  fi
else
  printf 'Project file not found: %s\n' "${PBXPROJ_FILE}"
fi

print_section "Next real-device checks"
cat <<'CHECKS'
1. Xcode > Settings > Accounts: add Apple ID and create Apple Development certificate.
2. Connect the iPhone by USB, unlock it, and trust this Mac.
3. Enable Developer Mode on the iPhone if iOS asks for it.
4. In DailyLang target Signing & Capabilities, choose your Team.
5. Select the iPhone run destination and press Run.
6. In the app, open Settings > On-device Diagnostics before testing capture.
CHECKS
