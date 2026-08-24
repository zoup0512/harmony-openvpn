#!/bin/bash
# Cross-compile OpenSSL 3.4.1 static libs for aarch64-linux-ohos using DevEco clang.
set -e
TC="$(cygpath -m "$(cygpath -d 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native')")"
ROOT="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
SRC="$ROOT/third_party/openssl"
OUT="$ROOT/build/openssl-ohos"
MAKE="E:/AndroidSdk/ndk/25.1.8937393/prebuilt/windows-x86_64/bin/make.exe"

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$OUT"

export CC="$TC/llvm/bin/clang.exe --target=aarch64-linux-ohos --sysroot=$TC/sysroot"
export CFLAGS="-fPIC -O2"
export AR="$TC/llvm/bin/llvm-ar.exe"
export RANLIB="$TC/llvm/bin/llvm-ranlib.exe"
export PERL=$(which perl)
export PERL5LIB="$(cygpath -u "$ROOT")/perl_libs"
# stop MSYS from rewriting PERL5LIB into D:/... for the native make.exe
# (msys perl would then split it on the drive colon)
export MSYS2_ENV_CONV_EXCL="PERL5LIB"

perl "$SRC/Configure" linux-aarch64 no-shared no-tests no-docs no-apps no-legacy --prefix="$OUT/install" --libdir=lib

$MAKE -j8 build_libs
$MAKE install_dev
echo "OPENSSL_BUILD_OK"
