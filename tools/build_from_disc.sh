#!/usr/bin/env bash
# From your own game disc to the Switch's SD card folder, in one command: every step of the README's Building and
# Switch sections, each skipped when it is already done, so the script can simply be run again.
#
#   tools/build_from_disc.sh <your extracted disc folder | your .iso> [options]
#
#   --jobs N            compile jobs (default 4: the translated game needs about 10 GB of memory at -j 4)
#
# Result: out/nx/sdcard/switch/alice-nx (the NRO, the shader cache and your game files): copy out/nx/sdcard/switch to
# the card's root.
#
# The game's shaders: every one is extracted from the game's cooked packages (tools/renut/extract_shaders.sh), so no
# playing is needed. The PC build translates them, tools/renut/switch_shaders.sh makes their Switch form, and
# tools/renut/precompile_all_variants.py compiles every variant a draw can need into deko3d_shaders.bin, so the
# console compiles none while playing.
#
# Needs: Linux x86-64 with clang, CMake 3.25+, Ninja, Python 3, Git, a Vulkan driver, the
# X11/XCB and Wayland development files, and devkitPro (devkitA64, libnx, deko3d, switch-tools).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="$root/sdk"
jobs=4
game=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) jobs="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) game="$1"; shift ;;
  esac
done
step() { printf '\n\033[1;35m== %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

step "Checking the tools"
for t in clang cmake ninja python3 git; do command -v "$t" >/dev/null || die "missing: $t"; done
export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
[[ -x "$DEVKITPRO/devkitA64/bin/aarch64-none-elf-gcc" ]] || die "missing: devkitPro's devkitA64 at $DEVKITPRO (set DEVKITPRO)"

step "Your game"
mkdir -p "$root/assets"
if [[ -e "$root/assets/game_root/Default.xex" || -e "$root/assets/game_root/default.xex" ]]; then
  echo "assets/game_root is already set up"
  [[ -z "$game" ]] || echo "(ignoring $game: delete assets/game_root to use another copy)"
else
  [[ -n "$game" ]] || die "give your extracted disc folder or your .iso: tools/build_from_disc.sh /path/to/game"
  if [[ -f "$game" ]]; then
    python3 "$root/tools/extract_iso.py" "$game" -o "$root/assets/game_root"
  else
    [[ -e "$game/Default.xex" || -e "$game/default.xex" ]] || die "no Default.xex in $game"
    ln -sfn "$(cd "$game" && pwd)" "$root/assets/game_root"
  fi
fi

step "The in-tree ReXGlue SDK and shader tools (once)"
[[ -x "$sdk/out/linux-amd64/rexglue" ]] || "$root/tools/build_sdk.sh" -j "$jobs"
"$root/tools/fetch_dxc.sh"
[[ -x "$root/out/deko3d_tools/uam-build/uam" && -x "$root/out/deko3d_tools/spirv-cross-build/spirv-cross" ]] || "$root/tools/deko3d_build_tools.sh"

step "Translating the game's code (about 3 minutes)"
"$root/tools/codegen.sh"

step "Every shader from the game's packages"
"$root/tools/renut/extract_shaders.sh"

step "The shaders, translated on this PC (the game itself is not built for the PC)"
"$root/tools/host_shaders.sh" -j "$jobs"

step "The game's shaders for the Switch"
"$root/tools/renut/switch_shaders.sh"

step "Every shader variant, compiled for the console (the longest step)"
# Made again whenever switch_shaders.sh remade the shaders (an update), so the cache never lags behind the NRO.
cache="$root/out/deko3d_shaders/deko3d_shaders.bin"
if [[ ! -f "$cache" || "$root/out/deko3d_shaders/glsl_opt" -nt "$cache" ]]; then
  python3 -I "$root/tools/renut/precompile_all_variants.py" --jobs "$jobs"
else
  echo "deko3d_shaders.bin is up to date"
fi

step "The Switch build"
"$root/tools/build_switch.sh" -j "$jobs"
python3 "$root/tools/check_switch_build.py" --sdk-vulkan /nonexistent | tail -n 1

step "The SD card folder"
"$root/tools/package_switch.sh" --with-game

cat <<DONE

Done: $root/out/nx/sdcard/switch/alice-nx
Copy out/nx/sdcard/switch to the root of your Switch's SD card, then start the game from the homebrew menu opened
through a game (hold R while starting a game), not from the album. Everything in that folder is for your own console
only: never share it.
DONE
