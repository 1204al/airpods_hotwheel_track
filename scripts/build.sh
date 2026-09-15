#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
configuration="${1:-debug}"
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c "$configuration"
binary_dir="$(swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c "$configuration" --show-bin-path)"
app_path="$PWD/build/PodTrack.app"
mkdir -p "$PWD/build"
staging_dir="$(mktemp -d "$PWD/build/.package.XXXXXX")"
cleanup_package() {
    if [ -e "$staging_dir/Previous.app" ]; then
        printf 'Previous bundle preserved at %s\n' "$staging_dir/Previous.app" >&2
    else
        rm -rf "$staging_dir"
    fi
}
trap cleanup_package EXIT
staged_app="$staging_dir/PodTrack.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/PodTrack" "$staged_app/Contents/MacOS/PodTrack"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
for resource_bundle in "$binary_dir"/*.bundle; do
    if [ -d "$resource_bundle" ]; then
        cp -R "$resource_bundle" "$staged_app/Contents/Resources/"
    fi
done
plutil -lint "$staged_app/Contents/Info.plist"
codesign --force --sign - --identifier dev.podtrack.mac "$staged_app"
codesign --verify --deep --strict "$staged_app"

# Publish a complete, verified bundle with a fresh Finder modification date.
# Never overwrite the executable of a running instance in place.
if [ -e "$app_path" ]; then
    mv "$app_path" "$staging_dir/Previous.app"
fi
if ! mv "$staged_app" "$app_path"; then
    if [ -e "$staging_dir/Previous.app" ]; then
        mv "$staging_dir/Previous.app" "$app_path"
    fi
    exit 1
fi
rm -rf "$staging_dir/Previous.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
printf 'Built PodTrack %s (%s)\n%s\n' "$version" "$build_number" "$app_path"
printf '\nQuit the running PodTrack with Command-Q, then reopen this bundle.\nClosing its window or opening the app again does not restart an existing process.\n'
