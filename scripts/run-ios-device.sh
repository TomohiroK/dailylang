#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_FILE="${PROJECT_ROOT}/DailyLang.xcodeproj"
readonly SCHEME_NAME="DailyLang"
readonly PRODUCT_NAME="DailyLang"
readonly BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.tomohirok.dailylang}"
readonly CONFIGURATION="${CONFIGURATION:-Debug}"
readonly DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_ROOT}/.build/XcodeDerivedDataRealDevice}"
readonly SOURCE_PACKAGES_PATH="${SOURCE_PACKAGES_PATH:-${PROJECT_ROOT}/.build/SourcePackages}"
readonly OPENAI_ENV_FILE="${OPENAI_ENV_FILE:-${PROJECT_ROOT}/.env.local}"
readonly SIGNING_PREFLIGHT="${SIGNING_PREFLIGHT:-1}"

usage() {
  cat <<USAGE
Usage:
  DEVICE_ID=<device-udid> scripts/run-ios-device.sh [launch arguments...]
  scripts/run-ios-device.sh <device-udid> [launch arguments...]

Optional environment variables:
  DEVELOPMENT_TEAM=<team-id>         Override the Xcode signing team.
  ALLOW_PROVISIONING_UPDATES=0       Disable automatic provisioning updates.
  ALLOW_DEVICE_REGISTRATION=1        Allow Xcode to register the device.
  SKIP_LAUNCH=1                      Install without launching.
  SIGNING_PREFLIGHT=0                Skip the local code-signing identity preflight.
  OPENAI_ENV_FILE=<path>             Env file containing OPENAI_API_KEY.

Default launch argument:
  -DailyLangOpenSettings
USAGE
}

check_signing_identity() {
  if [[ "${SIGNING_PREFLIGHT}" == "0" ]]; then
    return
  fi

  local identities
  if ! identities="$(security find-identity -v -p codesigning 2>/dev/null)"; then
    printf 'Could not read code signing identities from Keychain.\n' >&2
    printf 'Run bash scripts/check-ios-device-readiness.sh and fix Keychain/Xcode account access first.\n' >&2
    exit 3
  fi

  if printf '%s\n' "${identities}" | grep -q "0 valid identities found"; then
    printf 'No valid code signing identities were found in Keychain.\n' >&2
    printf 'Open Xcode > Settings > Accounts > Manage Certificates and create an Apple Development certificate.\n' >&2
    printf 'Then rerun: bash scripts/check-ios-device-readiness.sh\n' >&2
    exit 3
  fi
}

load_openai_env_if_available() {
  if [[ -f "${OPENAI_ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${OPENAI_ENV_FILE}"
    set +a
  fi

  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    export DEVICECTL_CHILD_OPENAI_API_KEY="${OPENAI_API_KEY}"
  fi
}

device_id="${DEVICE_ID:-}"
if [[ -z "${device_id}" && $# -gt 0 ]]; then
  device_id="$1"
  shift
fi

if [[ -z "${device_id}" ]]; then
  usage
  printf '\nRun scripts/check-ios-device-readiness.sh to find a connected device UDID.\n'
  exit 2
fi

check_signing_identity

launch_args=("$@")
if [[ ${#launch_args[@]} -eq 0 ]]; then
  launch_args=("-DailyLangOpenSettings")
fi

xcodebuild_args=(
  -project "${PROJECT_FILE}"
  -scheme "${SCHEME_NAME}"
  -configuration "${CONFIGURATION}"
  -sdk iphoneos
  -destination "id=${device_id}"
  -destination-timeout 60
  -derivedDataPath "${DERIVED_DATA_PATH}"
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_PATH}"
)

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  xcodebuild_args+=("DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}")
fi

if [[ "${ALLOW_PROVISIONING_UPDATES:-1}" != "0" ]]; then
  xcodebuild_args+=("-allowProvisioningUpdates")
fi
if [[ "${ALLOW_DEVICE_REGISTRATION:-0}" == "1" ]]; then
  xcodebuild_args+=("-allowProvisioningDeviceRegistration")
fi

printf 'Building %s for device %s...\n' "${SCHEME_NAME}" "${device_id}"
xcodebuild "${xcodebuild_args[@]}" build

app_path="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-iphoneos/${PRODUCT_NAME}.app"
if [[ ! -d "${app_path}" ]]; then
  app_path="$(find "${DERIVED_DATA_PATH}/Build/Products" -name "${PRODUCT_NAME}.app" -type d -print -quit)"
fi

if [[ -z "${app_path}" || ! -d "${app_path}" ]]; then
  printf 'Built app was not found under %s.\n' "${DERIVED_DATA_PATH}" >&2
  exit 1
fi

printf 'Installing %s...\n' "${app_path}"
xcrun devicectl device install app --device "${device_id}" "${app_path}"

if [[ "${SKIP_LAUNCH:-0}" == "1" ]]; then
  printf 'Installed. Launch skipped because SKIP_LAUNCH=1.\n'
  exit 0
fi

load_openai_env_if_available

printf 'Launching %s %s...\n' "${BUNDLE_IDENTIFIER}" "${launch_args[*]}"
xcrun devicectl device process launch \
  --device "${device_id}" \
  --terminate-existing \
  "${BUNDLE_IDENTIFIER}" \
  -- \
  "${launch_args[@]}"
