#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${1:-iphoneos}"
case "$SDK" in
  iphoneos) ARCH=arm64; OPENSSL_TARGET=ios64-xcrun; MIN_FLAG=-miphoneos-version-min=16.0 ;;
  iphonesimulator)
    ARCH="$(uname -m)"
    OPENSSL_TARGET="iossimulator-$ARCH-xcrun"; MIN_FLAG=-mios-simulator-version-min=16.0 ;;
  *) echo "Unsupported SDK: $SDK" >&2; exit 1 ;;
esac
python3 "$ROOT/scripts/fetch_dependencies.py"
PREFIX="$ROOT/.deps/$SDK"
mkdir -p "$ROOT/build/openssl-$SDK" "$PREFIX"
SDKROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
export SDKROOT
pushd "$ROOT/build/openssl-$SDK" >/dev/null
perl "$ROOT/.deps/src/openssl/Configure" "$OPENSSL_TARGET" no-shared no-tests no-apps no-module \
  --prefix="$PREFIX" --libdir=lib "$MIN_FLAG"
make -j "$(sysctl -n hw.logicalcpu)" build_libs
make install_dev
popd >/dev/null
cmake -S "$ROOT" -B "$ROOT/build/core-$SDK" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$SDKROOT" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DOPENSSL_ROOT_DIR="$PREFIX" \
  -DOPENSSL_USE_STATIC_LIBS=TRUE -DBUILD_TESTING=OFF -DRECEIVER_BUILD_UPSTREAM=ON
cmake --build "$ROOT/build/core-$SDK" --config Release -- CODE_SIGNING_ALLOWED=NO
cmake --install "$ROOT/build/core-$SDK" --config Release
