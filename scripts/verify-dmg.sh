#!/usr/bin/env bash
#
# Post-mortem verification of a release image: mount it and assert that what a
# user would drag into /Applications is what we think we built. "It compiled" is
# not evidence — the failures this catches surface at the user as "the app is
# damaged and can't be opened".
#
# Usage: verify-dmg.sh <image.dmg> [--expect-version X.Y.Z] [--skip-security]
#
# --skip-security drops the Gatekeeper triad. It is correct only for an unsigned
# build; a signed release must never pass it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/product.env
. "${ROOT}/scripts/product.env"

DMG=""
EXPECT_VERSION=""
SKIP_SECURITY=0

while [ $# -gt 0 ]; do
	case "$1" in
	--expect-version)
		EXPECT_VERSION="$2"
		shift 2
		;;
	--skip-security)
		SKIP_SECURITY=1
		shift
		;;
	-*)
		echo "error: unknown option $1" >&2
		exit 2
		;;
	*)
		DMG="$1"
		shift
		;;
	esac
done

if [ -z "${DMG}" ] || [ ! -f "${DMG}" ]; then
	echo "error: usage: verify-dmg.sh <image.dmg> [--expect-version X.Y.Z] [--skip-security]" >&2
	exit 2
fi

MOUNT_DIR="$(mktemp -d)"

detach() {
	# hdiutil detach loses to Spotlight and friends often enough to need retries.
	for _ in 1 2 3 4 5; do
		if hdiutil detach "${MOUNT_DIR}" -quiet 2>/dev/null; then
			break
		fi
		sleep 2
	done
	rmdir "${MOUNT_DIR}" 2>/dev/null || true
}
trap detach EXIT

hdiutil attach "${DMG}" -readonly -nobrowse -noautoopen -mountpoint "${MOUNT_DIR}" -quiet

APP="${MOUNT_DIR}/${PRODUCT_NAME}.app"
fail() {
	echo "FAIL: $1" >&2
	exit 1
}

[ -d "${APP}" ] || fail "${PRODUCT_NAME}.app is not on the image"
[ -L "${MOUNT_DIR}/Applications" ] || fail "the /Applications drop target is missing"
[ "$(readlink "${MOUNT_DIR}/Applications")" = "/Applications" ] ||
	fail "the Applications symlink does not point at /Applications"
[ -x "${APP}/Contents/MacOS/${PRODUCT_NAME}" ] || fail "the bundle executable is missing"
file "${APP}/Contents/MacOS/${PRODUCT_NAME}" | grep -q 'Mach-O' ||
	fail "the bundle executable is not a Mach-O binary"

PLIST="${APP}/Contents/Info.plist"
ACTUAL_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${PLIST}")"
[ "${ACTUAL_ID}" = "${BUNDLE_ID}" ] ||
	fail "bundle identifier is ${ACTUAL_ID}, expected ${BUNDLE_ID}"

ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}")"
case "${ACTUAL_VERSION}" in
'' | '$'*) fail "CFBundleShortVersionString was not substituted: ${ACTUAL_VERSION}" ;;
esac
if [ -n "${EXPECT_VERSION}" ] && [ "${ACTUAL_VERSION}" != "${EXPECT_VERSION}" ]; then
	fail "version is ${ACTUAL_VERSION}, expected ${EXPECT_VERSION}"
fi

echo "ok: ${PRODUCT_NAME}.app ${ACTUAL_VERSION} (${ACTUAL_ID})"

if [ "${SKIP_SECURITY}" -eq 1 ]; then
	echo "skipped: signature, notarization and Gatekeeper checks (unsigned build)"
	exit 0
fi

codesign --verify --deep --strict --verbose=2 "${APP}" || fail "codesign verification failed"
xcrun stapler validate "${APP}" || fail "the notarization ticket is not stapled to the app"
spctl --assess --type execute --verbose=4 "${APP}" || fail "Gatekeeper rejected the app"

echo "ok: signed, notarized and accepted by Gatekeeper"
