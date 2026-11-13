#!/usr/bin/env bash
# Configures (first time) and builds the Nintendo Switch NRO: out/nx/alice.nro (sa2-nx's tools/win/build_switch.ps1,
# for Linux). Logs: out/nx_configure.log, out/nx_build.log.
#
# Before the first build: tools/codegen.sh (the generated code), tools/host_shaders.sh (the game's shaders),
# tools/deko3d_build_tools.sh and tools/renut/switch_shaders.sh.
#
# Renut draws on deko3d, so the NRO has no Vulkan driver (REXGLUE_SWITCH_NO_NVK). The SDK and plume still want an
# "NVK SDK" folder for their checks and Vulkan headers: out/nvk-stub holds the Khronos headers of the SDK and an empty
# libvulkan.a that is never linked.
#
#   tools/build_switch.sh [-j N]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
sa2="${SA2_NX:-$root/../sa2-nx}"
build="$root/out/nx"
jobs="${2:-$(nproc)}"
# Renut is the console's only renderer (there is no emulated GPU there). ALICE_RENUT=OFF builds an NRO without it,
# which only checks that the game's code compiles and links for the console.
renut="${ALICE_RENUT:-ON}"
export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
stub="$root/out/nvk-stub"
if [[ ! -f "$stub/lib/libvulkan.a" ]]; then
  mkdir -p "$stub/lib"
  ln -sfn "$sa2/sdk/thirdparty/vulkan-headers/include" "$stub/include"
  "$DEVKITPRO/devkitA64/bin/aarch64-none-elf-ar" rcs "$stub/lib/libvulkan.a"
fi
mkdir -p "$root/out"
# The homebrew menu icon: your disc's dashboard art (tools/disc_icon.py; game art, in out/ only), else the project's.
python3 "$root/tools/disc_icon.py" "$root/assets/game_root" "$root/out/nx_icon.jpg"
if [[ ! -f "$build/build.ninja" ]]; then
  cmake -S "$root/app" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$sa2/tools/switch/cmake/switch-devkitA64.cmake" -DDEVKITPRO="$DEVKITPRO" \
    -DREXSDK_DIR="$sa2/sdk" -DREXGLUE_SWITCH_NVK_SDK="$stub" -DREXGLUE_SWITCH_NO_NVK=ON -DALICE_RENUT_RENDERER="$renut" \
    > "$root/out/nx_configure.log" 2>&1 || { tail -n 40 "$root/out/nx_configure.log"; exit 1; }
else
  # An existing tree keeps its cache: ALICE_RENUT is applied again on every run (before 2026-11-02 only the first
  # configure took it, so ALICE_RENUT=ON on a tree configured without Renut built an NRO with no renderer).
  cmake -S "$root/app" -B "$build" -DALICE_RENUT_RENDERER="$renut" > "$root/out/nx_configure.log" 2>&1 ||
    { tail -n 40 "$root/out/nx_configure.log"; exit 1; }
fi
grep -q "^ALICE_RENUT_RENDERER:BOOL=$renut\$" "$build/CMakeCache.txt" ||
  { echo "out/nx is not configured with ALICE_RENUT_RENDERER=$renut" >&2; exit 1; }
set +e
cmake --build "$build" --target alice -j "$jobs" > "$root/out/nx_build.log" 2>&1
code=$?
set -e
grep -E 'error:|FAILED|undefined reference' "$root/out/nx_build.log" | head -n 40 || true
tail -n 3 "$root/out/nx_build.log"
[[ $code -eq 0 ]] && ls -la "$build/alice.nro"
exit $code
