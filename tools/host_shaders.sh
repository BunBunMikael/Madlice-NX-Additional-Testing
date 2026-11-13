#!/usr/bin/env bash
# The game's shaders, translated on this PC for the Switch build: configures the host tree out/pc (clang) and builds
# only Renut's shader target, renut_shader_cache_gen. It builds Renut's XenosRecomp (a PC tool), gathers the shader
# containers of out/pc/shader_capture into out/renut_shader_dump (tools/renut/extract_shaders.sh puts them there),
# and translates them: out/pc/renut_gpu/shader_cache.cpp and early_alpha_hlsl/, which tools/renut/switch_shaders.sh
# turns into the Switch's form. The game itself is not compiled for the PC. Game data: out/ only, never committed.
# Logs: out/pc_configure.log, out/host_shaders.log.
#
#   tools/host_shaders.sh [-j N]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
sa2="${SA2_NX:-$root/../sa2-nx}"
build="$root/out/pc"
jobs="${2:-$(nproc)}"
mkdir -p "$root/out"
if [[ ! -f "$build/build.ninja" ]]; then
  cmake -S "$root/app" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DALICE_RENUT_RENDERER=ON \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_FLAGS=-march=x86-64-v2 -DCMAKE_CXX_FLAGS=-march=x86-64-v2 \
    -DREXSDK_DIR="$sa2/sdk" > "$root/out/pc_configure.log" 2>&1 \
    || { tail -n 30 "$root/out/pc_configure.log"; exit 1; }
fi
set +e
cmake --build "$build" --target renut_shader_cache_gen -j "$jobs" > "$root/out/host_shaders.log" 2>&1
code=$?
set -e
grep -E 'error:|FAILED' "$root/out/host_shaders.log" | head -n 40 || true  # no match is the good case
tail -n 3 "$root/out/host_shaders.log"
exit $code
