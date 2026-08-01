#!/usr/bin/env bash
#
# Assemble the .app bundle from the SwiftPM executable.
#
# This is the only description of the bundle: CI and the release pipeline run
# this exact script, so a bundle that works locally works in a release.
#
# Environment:
#   CONFIGURATION   swift build configuration            (default: release)
#   VERSION         CFBundleShortVersionString           (default: version.txt)
#   BUILD           CFBundleVersion, must be monotonic   (default: $GITHUB_RUN_NUMBER, else 0)
#   SIGN_IDENTITY   codesign identity, "-" is ad-hoc     (default: -)
#   ENTITLEMENTS    entitlements plist                   (default: autodetected)
#   OUTPUT_DIR      where the .app lands                 (default: ./build)
#   EXECUTABLE_NAME SwiftPM product name                 (default: autodetected)
# Plus PRODUCT_NAME / BUNDLE_ID / MIN_MACOS / COPYRIGHT from scripts/product.env.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/product.env
. "${ROOT}/scripts/product.env"

CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT}/build}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUILD="${BUILD:-${GITHUB_RUN_NUMBER:-0}}"
if [ -z "${VERSION:-}" ]; then
	VERSION="$(cat "${ROOT}/version.txt" 2>/dev/null || echo "0.0.0")"
fi

APP="${OUTPUT_DIR}/${PRODUCT_NAME}.app"
CONTENTS="${APP}/Contents"

cd "${ROOT}"

# --- compile -----------------------------------------------------------------

echo "==> swift build -c ${CONFIGURATION}"
swift build -c "${CONFIGURATION}"
BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"

# The binary is named after the SwiftPM product (or the executable target when
# there is no explicit product), which need not match the product name we ship.
if [ -z "${EXECUTABLE_NAME:-}" ]; then
	EXECUTABLE_NAME="$(swift package describe --type json | python3 -c '
import json, sys

description = json.load(sys.stdin)


def is_executable(kind):
    return kind == "executable" or (isinstance(kind, dict) and "executable" in kind)


for group in ("products", "targets"):
    for item in description.get(group, []):
        if is_executable(item.get("type")):
            print(item["name"])
            raise SystemExit(0)
raise SystemExit("no executable product or target in Package.swift")
')"
fi

EXECUTABLE="${BIN_DIR}/${EXECUTABLE_NAME}"
[ -x "${EXECUTABLE}" ] || {
	echo "error: ${EXECUTABLE} is missing or not executable" >&2
	exit 1
}

# --- assemble ----------------------------------------------------------------

echo "==> assembling ${APP} (version ${VERSION}, build ${BUILD})"
rm -rf "${APP}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp "${EXECUTABLE}" "${CONTENTS}/MacOS/${PRODUCT_NAME}"

# SwiftPM emits resource bundles next to the binary. Bundle.module looks for them
# in the main bundle's resource path, so Contents/Resources is where they belong.
for resource_bundle in "${BIN_DIR}"/*.bundle; do
	if [ -e "${resource_bundle}" ]; then
		cp -R "${resource_bundle}" "${CONTENTS}/Resources/"
	fi
done

ICON="$(find "${ROOT}/Sources" "${ROOT}/Resources" \
	-name 'AppIcon.icns' -print -quit 2>/dev/null || true)"
if [ -n "${ICON}" ]; then
	cp "${ICON}" "${CONTENTS}/Resources/AppIcon.icns"
else
	echo "warning: no AppIcon.icns found — the bundle ships without an icon" >&2
fi

sed \
	-e '/<!--/,/-->/d' \
	-e "s|\${PRODUCT_NAME}|${PRODUCT_NAME}|g" \
	-e "s|\${BUNDLE_ID}|${BUNDLE_ID}|g" \
	-e "s|\${VERSION}|${VERSION}|g" \
	-e "s|\${BUILD}|${BUILD}|g" \
	-e "s|\${MIN_MACOS}|${MIN_MACOS}|g" \
	-e "s|\${COPYRIGHT}|${COPYRIGHT}|g" \
	"${ROOT}/Resources/Info.plist.in" >"${CONTENTS}/Info.plist"

printf 'APPL????' >"${CONTENTS}/PkgInfo"

# --- sign --------------------------------------------------------------------

if [ -z "${ENTITLEMENTS:-}" ]; then
	ENTITLEMENTS="$(find "${ROOT}" -maxdepth 2 -name '*.entitlements' \
		-not -path '*/.build/*' -not -path '*/build/*' -print -quit 2>/dev/null || true)"
fi

sign_args=(--force --sign "${SIGN_IDENTITY}")
if [ "${SIGN_IDENTITY}" != "-" ]; then
	# Hardened runtime and a secure timestamp are preconditions for notarization.
	sign_args+=(--options runtime --timestamp)
fi
if [ -n "${ENTITLEMENTS}" ] && [ -f "${ENTITLEMENTS}" ]; then
	sign_args+=(--entitlements "${ENTITLEMENTS}")
fi

# Nested code first, then the bundle: signing the outside seals the inside.
for nested in "${CONTENTS}/Resources"/*.bundle; do
	if [ -e "${nested}" ]; then
		codesign --force --sign "${SIGN_IDENTITY}" "${nested}"
	fi
done

# Always re-sign, even ad-hoc: SwiftPM leaves release binaries "linker-signed",
# and a bundle whose executable carries that signature fails validation.
echo "==> codesign (identity: ${SIGN_IDENTITY})"
codesign "${sign_args[@]}" "${APP}"

# --- verify ------------------------------------------------------------------

codesign --verify --strict --verbose=2 "${APP}"
[ -x "${CONTENTS}/MacOS/${PRODUCT_NAME}" ] || {
	echo "error: bundle executable is missing" >&2
	exit 1
}
file "${CONTENTS}/MacOS/${PRODUCT_NAME}" | grep -q 'Mach-O' || {
	echo "error: bundle executable is not a Mach-O binary" >&2
	exit 1
}
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${CONTENTS}/Info.plist" >/dev/null

echo "==> ${APP}"
