#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

VARIANT="${1:-mainline}"
CONFIG="${2:-Debug}"
ARCH="${3:-$(uname -m)}"

case "$VARIANT" in
    mainline | zs)
        VARIANTS="$VARIANT"
        ;;
    all)
        VARIANTS="mainline zs"
        ;;
    *)
        echo "usage: $0 [mainline|zs|all] [Debug|Release] [arm64|x86_64]" >&2
        exit 2
        ;;
esac

case "$CONFIG" in
    Debug | Release) ;;
    *)
        echo "error: configuration must be Debug or Release" >&2
        exit 2
        ;;
esac

case "$ARCH" in
    arm64 | x86_64) ;;
    *)
        echo "error: architecture must be arm64 or x86_64" >&2
        exit 2
        ;;
esac

SYMROOT="$ROOT/build/products"
OBJROOT="$ROOT/build/intermediates"
APPS_DIR="$ROOT/build/apps"

build_variant() {
    variant="$1"
    case "$variant" in
        mainline)
            scheme="ShichiZip"
            product="ShichiZip.app"
            ;;
        zs)
            scheme="ShichiZipZS"
            product="ShichiZip ZS.app"
            ;;
    esac

    echo "==> Building $scheme ($CONFIG, $ARCH)"
    xcodebuild \
        -project "$ROOT/ShichiZip.xcodeproj" \
        -scheme "$scheme" \
        -configuration "$CONFIG" \
        -arch "$ARCH" \
        SYMROOT="$SYMROOT" \
        OBJROOT="$OBJROOT" \
        build

    source_app="$SYMROOT/$CONFIG/$product"
    if [ ! -d "$source_app" ]; then
        echo "error: expected app bundle was not produced: $source_app" >&2
        exit 1
    fi

    mkdir -p "$APPS_DIR/$CONFIG"
    destination="$APPS_DIR/$CONFIG/$product"
    case "$destination" in
        "$APPS_DIR"/*) ;;
        *)
            echo "error: refusing to write outside $APPS_DIR" >&2
            exit 1
            ;;
    esac
    rm -rf "$destination"
    ditto "$source_app" "$destination"
    # ditto preserves the source bundle's directory mtime, which can predate an
    # incremental rebuild; stamp the copy so Finder reflects the build time.
    touch "$destination"

    if [ -d "$source_app.dSYM" ]; then
        rm -rf "$destination.dSYM"
        ditto "$source_app.dSYM" "$destination.dSYM"
        touch "$destination.dSYM"
    fi

    echo "App: $destination"
}

for variant in $VARIANTS; do
    build_variant "$variant"
done
