#!/usr/bin/env bash
#
# Submit a .app or .dmg to Apple's notary service, wait for the verdict, and
# staple the ticket. Used twice per release — once for the app (so the ticket
# travels inside the image) and once for the image itself.
#
# Usage: notarize.sh <path-to-.app-or-.dmg>
#
# Requires APPLE_ID, APPLE_TEAM_ID and APPLE_APP_SPECIFIC_PASSWORD.

set -euo pipefail

TARGET="${1:?usage: notarize.sh <path-to-.app-or-.dmg>}"
: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

case "${TARGET}" in
*.app)
	# The notary service takes archives, not bundles; --keepParent preserves the
	# .app directory inside the zip.
	UPLOAD="${WORK}/$(basename "${TARGET}").zip"
	ditto -c -k --keepParent "${TARGET}" "${UPLOAD}"
	;;
*)
	UPLOAD="${TARGET}"
	;;
esac

LOG="${WORK}/notarytool.txt"
set +e
xcrun notarytool submit "${UPLOAD}" \
	--apple-id "${APPLE_ID}" \
	--team-id "${APPLE_TEAM_ID}" \
	--password "${APPLE_APP_SPECIFIC_PASSWORD}" \
	--wait | tee "${LOG}"
submit_status=${PIPESTATUS[0]}
set -e

SUBMISSION_ID="$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "${LOG}" | head -1 || true)"

# notarytool exits 0 even when the verdict is Invalid, so the status line is the
# only reliable signal. Pull the detailed log before failing — it is the only
# place that says which binary was rejected and why.
if [ "${submit_status}" -ne 0 ] || grep -qE 'status: (Invalid|Rejected)' "${LOG}"; then
	if [ -n "${SUBMISSION_ID}" ]; then
		echo "==> notarization failed; fetching the log for ${SUBMISSION_ID}"
		xcrun notarytool log "${SUBMISSION_ID}" \
			--apple-id "${APPLE_ID}" \
			--team-id "${APPLE_TEAM_ID}" \
			--password "${APPLE_APP_SPECIFIC_PASSWORD}" || true
	fi
	exit 1
fi

xcrun stapler staple "${TARGET}"
xcrun stapler validate "${TARGET}"
echo "==> notarized and stapled: ${TARGET}"
