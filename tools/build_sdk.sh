#!/usr/bin/env bash
# Build the in-tree Renut ReXGlue SDK and its code generator on Linux.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="$root/sdk"
jobs="${2:-$(nproc)}"
mkdir -p "$sdk/out"
cmake -S "$sdk" -B "$sdk/out/host" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_FLAGS=-march=x86-64-v2 -DCMAKE_CXX_FLAGS=-march=x86-64-v2 \
  > "$root/out_sdk_configure.log" 2>&1 || { tail -n 40 "$root/out_sdk_configure.log"; exit 1; }
cmake --build "$sdk/out/host" --target rexglue -j "$jobs" > "$root/out_sdk_build.log" 2>&1 \
  || { grep -E 'error:|FAILED' "$root/out_sdk_build.log" | head -n 50; exit 1; }
test -x "$sdk/out/linux-amd64/rexglue"
echo "built $sdk/out/linux-amd64/rexglue"
