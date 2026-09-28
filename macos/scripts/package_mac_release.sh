#!/usr/bin/env bash
set -euo pipefail

# Continuous Signing & Release Packaging for Curio macOS
# Builds, codesigns (inside-out with hardened runtime), strictly verifies,
# packages into DMG + ZIP, and optionally notarizes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${MACOS_DIR}/.." && pwd)"

OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/build/macos_release}"
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
CONFIGURATION="${CONFIGURATION:-Release}"

echo "=== Curio macOS Continuous Signing & Packaging ==="
echo "Workspace Root:   ${ROOT_DIR}"
echo "macOS Dir:        ${MACOS_DIR}"
echo "Output Directory: ${OUTPUT_DIR}"
echo "Signing Identity: ${SIGNING_IDENTITY}"
echo "Configuration:    ${CONFIGURATION}"

mkdir -p "${OUTPUT_DIR}"

# 1. Ensure macOS app icon assets exist
if [ ! -f "${MACOS_DIR}/CurioMac/AppIcon.icns" ] || [ ! -d "${MACOS_DIR}/CurioMac/Assets.xcassets/AppIcon.appiconset" ]; then
    echo ""
    echo "--> Generating macOS AppIcon assets..."
    python3 "${ROOT_DIR}/tools/gen_mac_app_icon.py"
fi

# 2. Regenerate Xcode project with XcodeGen
echo ""
echo "--> Generating Xcode project..."
(cd "${MACOS_DIR}" && xcodegen generate)

# 3. Build the Mac app & embedded MCP tool
echo ""
echo "--> Building CurioMac (${CONFIGURATION})..."
DERIVED_DATA="${OUTPUT_DIR}/DerivedData"
rm -rf "${DERIVED_DATA}"

xcodebuild build \
    -project "${MACOS_DIR}/CurioMac.xcodeproj" \
    -scheme CurioMac \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}" \
    CODE_SIGN_STYLE="Manual" \
    ENABLE_HARDENED_RUNTIME=YES \
    -quiet

BUILT_APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/Curio.app"
if [ ! -d "${BUILT_APP}" ]; then
    echo "ERROR: Built application not found at ${BUILT_APP}" >&2
    exit 1
fi

echo "Found built app at: ${BUILT_APP}"

# 4. Inject OAuth Client if Info.plist needs updating
echo ""
echo "--> Running OAuth Client injection..."
TARGET_BUILD_DIR="${DERIVED_DATA}/Build/Products/${CONFIGURATION}" \
INFOPLIST_PATH="Curio.app/Contents/Info.plist" \
SRCROOT="${MACOS_DIR}" \
python3 "${SCRIPT_DIR}/inject_oauth_client.py"

# 4b. Ensure AppIcon.icns is present in Resources
if [ -f "${MACOS_DIR}/CurioMac/AppIcon.icns" ]; then
    echo "--> Ensuring AppIcon.icns in ${BUILT_APP}/Contents/Resources..."
    mkdir -p "${BUILT_APP}/Contents/Resources"
    cp "${MACOS_DIR}/CurioMac/AppIcon.icns" "${BUILT_APP}/Contents/Resources/AppIcon.icns"
fi

# 5. Inside-out Code Signing Pass with Hardened Runtime
echo ""
echo "--> Performing inside-out codesigning..."

TIMESTAMP_FLAG="--timestamp"
if [ "${SIGNING_IDENTITY}" = "-" ]; then
    TIMESTAMP_FLAG="" # ad-hoc signatures do not use timestamp servers
fi

# 4a. Sign embedded helper tools first
HELPER_BIN="${BUILT_APP}/Contents/MacOS/curio-mcp"
if [ -f "${HELPER_BIN}" ]; then
    echo "Signing helper: curio-mcp"
    codesign --force \
        --options runtime \
        ${TIMESTAMP_FLAG} \
        --entitlements "${MACOS_DIR}/CurioMCP/curio-mcp.entitlements" \
        --sign "${SIGNING_IDENTITY}" \
        "${HELPER_BIN}"
fi

# 4b. Sign any embedded frameworks/dylibs if present
find "${BUILT_APP}/Contents/Frameworks" -mindepth 1 -maxdepth 1 \( -name "*.dylib" -o -name "*.framework" \) 2>/dev/null | while read -r item; do
    echo "Signing framework: $(basename "${item}")"
    codesign --force \
        --options runtime \
        ${TIMESTAMP_FLAG} \
        --sign "${SIGNING_IDENTITY}" \
        "${item}"
done || true

# 4c. Sign the outer application bundle
echo "Signing main bundle: Curio.app"
codesign --force \
    --options runtime \
    ${TIMESTAMP_FLAG} \
    --entitlements "${MACOS_DIR}/CurioMac/CurioMac.entitlements" \
    --sign "${SIGNING_IDENTITY}" \
    "${BUILT_APP}"

# 5. Strict Verification
echo ""
echo "--> Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "${BUILT_APP}"
echo "Code signature successfully verified!"

if [ "${SIGNING_IDENTITY}" != "-" ]; then
    echo "Checking gatekeeper acceptance with spctl..."
    spctl --assess --type exec -v "${BUILT_APP}" || echo "Note: Gatekeeper validation pending notarization."
fi

# 6. Create ZIP release archive
echo ""
echo "--> Packaging ZIP release..."
ZIP_PATH="${OUTPUT_DIR}/Curio-macOS.zip"
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${BUILT_APP}" "${ZIP_PATH}"
echo "Created: ${ZIP_PATH}"

# 7. Create DMG release archive with /Applications symlink
echo ""
echo "--> Packaging DMG release..."
DMG_STAGING="${OUTPUT_DIR}/dmg_staging"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"

cp -R "${BUILT_APP}" "${DMG_STAGING}/Curio.app"
ln -s /Applications "${DMG_STAGING}/Applications"
if [ -f "${MACOS_DIR}/CurioMac/AppIcon.icns" ]; then
    cp "${MACOS_DIR}/CurioMac/AppIcon.icns" "${DMG_STAGING}/.VolumeIcon.icns"
fi

DMG_PATH="${OUTPUT_DIR}/Curio-macOS.dmg"
rm -f "${DMG_PATH}"

hdiutil create -volname "Curio" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}" \
    -quiet

rm -rf "${DMG_STAGING}"
echo "Created: ${DMG_PATH}"

# 7b. Sign the DMG container
if [ "${SIGNING_IDENTITY}" != "-" ]; then
    echo "Signing DMG container..."
    codesign --force --sign "${SIGNING_IDENTITY}" ${TIMESTAMP_FLAG} "${DMG_PATH}"
fi

# 8. Notarization (if credentials present)
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo ""
    echo "--> Submitting to Apple Notary Service..."
    xcrun notarytool submit "${DMG_PATH}" \
        --apple-id "${APPLE_ID}" \
        --password "${APPLE_PASSWORD}" \
        --team-id "${APPLE_TEAM_ID}" \
        --wait

    echo "Stapling notarization ticket to DMG..."
    xcrun stapler staple "${DMG_PATH}"
    echo "Stapled successfully!"
else
    echo ""
    echo "--> Notarization skipped (APPLE_ID / APPLE_PASSWORD / APPLE_TEAM_ID not provided)."
    echo "    Release package is signed and ready for local installation or distribution."
fi

# 9. Output artifact manifest & checksums
echo ""
echo "=== Packaging Complete ==="
echo "Artifacts in: ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"/*.zip "${OUTPUT_DIR}"/*.dmg
echo ""
echo "SHA256 Checksums:"
shasum -a 256 "${OUTPUT_DIR}"/Curio-macOS.*
