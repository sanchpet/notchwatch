#!/usr/bin/env bash
#
# Package the .app into a distributable disk image using system tools only —
# no Homebrew create-dmg — so the release path has no external dependency.
#
# The image is deliberately plain: the app plus a symlink to /Applications. A
# branded background needs artwork the fork does not have yet.
#
# Environment:
#   APP_PATH    the bundle to package        (default: build/<PRODUCT_NAME>.app)
#   DMG_PATH    output image                 (default: dist/<PRODUCT_NAME>-<version>.dmg)
#   VOLUME_NAME mounted volume name          (default: <PRODUCT_NAME>)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/product.env
. "${ROOT}/scripts/product.env"

APP_PATH="${APP_PATH:-${ROOT}/build/${PRODUCT_NAME}.app}"
VOLUME_NAME="${VOLUME_NAME:-${PRODUCT_NAME}}"

[ -d "${APP_PATH}" ] || {
	echo "error: ${APP_PATH} not found — run scripts/build-app.sh first" >&2
	exit 1
}

if [ -z "${DMG_PATH:-}" ]; then
	VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
		"${APP_PATH}/Contents/Info.plist")"
	DMG_PATH="${ROOT}/dist/${PRODUCT_NAME}-${VERSION}.dmg"
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

# ditto, not cp: it preserves extended attributes and the code signature.
ditto "${APP_PATH}" "${STAGING}/$(basename "${APP_PATH}")"
ln -s /Applications "${STAGING}/Applications"

mkdir -p "$(dirname "${DMG_PATH}")"
rm -f "${DMG_PATH}"

echo "==> hdiutil create ${DMG_PATH}"
hdiutil create \
	-volname "${VOLUME_NAME}" \
	-srcfolder "${STAGING}" \
	-fs HFS+ \
	-format UDZO \
	-imagekey zlib-level=9 \
	-ov \
	-quiet \
	"${DMG_PATH}"

hdiutil verify -quiet "${DMG_PATH}"

echo "==> ${DMG_PATH}"
