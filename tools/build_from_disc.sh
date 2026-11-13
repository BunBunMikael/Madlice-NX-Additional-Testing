#!/usr/bin/env bash
# From your own game disc to the Switch's SD card folder, in one command: every step of the README's Building and
# Switch sections, each skipped when it is already done, so the script can simply be run again.
#
#   tools/build_from_disc.sh <your extracted disc folder | your .iso> [options]
#
#   --jobs N            compile jobs (default 4: the translated game needs about 10 GB of memory at -j 4)
#   --nro-only          stop after the NRO is built and checked, before the shader cache (the longest step): the
#                       NRO does not need the cache to run, the console just compiles variants while playing
#   --shaders-only      the rest after --nro-only: the shader cache and the SD card folder
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
sa2="${SA2_NX:-$root/../sa2-nx}"
sa2_commit="adf3a4eee524dcca5cd7c1b42454ddb8a09124a1"
jobs=4
nro_only=0
shaders_only=0
game=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) jobs="$2"; shift 2 ;;
    --nro-only) nro_only=1; shift ;;
    --shaders-only) shaders_only=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) game="$1"; shift ;;
  esac
done
step() { printf '\n\033[1;35m== %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

step "Checking the tools"
for t in clang cmake ninja python3 git; do command -v "$t" >/dev/null || die "missing: $t"; done
export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
[[ -x "$DEVKITPRO/devkitA64/bin/aarch64-none-elf-gcc" ]] || die "missing: devkitPro's devkitA64 at $DEVKITPRO (set DEVKITPRO)"

if (( ! shaders_only )); then
  step "Your game"
  mkdir -p "$root/assets"
  if [[ -e "$root/assets/game_root/Default.xex" || -e "$root/assets/game_root/default.xex" ]]; then
    echo "assets/game_root is already set up"
    [[ -z "$game" ]] || echo "(ignoring $game: delete assets/game_root to use another copy)"
  else
    [[ -n "$game" ]] || die "give your extracted disc folder or your .iso: tools/build_from_disc.sh /path/to/game"
    if [[ -f "$game" ]]; then
      [[ -d "$sa2" ]] || git clone https://github.com/ChanseyIsTheBest/sa2-nx.git "$sa2"
      python3 "$sa2/tools/extract_iso.py" "$game" -o "$root/assets/game_root"
    else
      [[ -e "$game/Default.xex" || -e "$game/default.xex" ]] || die "no Default.xex in $game"
      ln -sfn "$(cd "$game" && pwd)" "$root/assets/game_root"
    fi
  fi

  step "sa2-nx (the SDK and tools), commit $sa2_commit"
  if [[ ! -d "$sa2/.git" ]]; then
    git clone https://github.com/ChanseyIsTheBest/sa2-nx.git "$sa2"
  fi
  if [[ "$(git -C "$sa2" rev-parse HEAD)" != "$sa2_commit" ]]; then
    git -C "$sa2" checkout -q "$sa2_commit" || die "could not check out $sa2_commit in $sa2 (local changes there?)"
  fi

  step "The code generator and shader tools (once)"
  [[ -x "$sa2/sdk/out/linux-amd64/rexglue" ]] || "$root/tools/build_sdk.sh" -j "$jobs"
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

  step "The Switch build"
  "$root/tools/build_switch.sh" -j "$jobs"
  # The check's verdict does not stop the run: the NRO is already built (it can be tried on a console while the shader
  # cache is made), so a failure is reported here and again at the very end, where it still fails the run.
  mkdir -p "$root/out"
  check=0
  python3 "$root/tools/check_switch_build.py" --sdk-vulkan /nonexistent > "$root/out/check_switch_build.log" 2>&1 || check=$?
  cat "$root/out/check_switch_build.log"
  echo "$check" > "$root/out/check_switch_build.rc"
  if (( check )); then
    echo "::warning::tools/check_switch_build.py failed (out/check_switch_build.log); the NRO is built, the run goes on"
  fi
  if (( nro_only )); then
    echo "--nro-only: stopping before the shader cache. The NRO: $root/out/nx/alice.nro"
    exit 0
  fi
else
  check="$(cat "$root/out/check_switch_build.rc" 2>/dev/null || echo 0)"
fi

step "Every shader variant, compiled for the console (the longest step)"
# Made again whenever switch_shaders.sh remade the shaders (an update), so the cache never lags behind the NRO.
cache="$root/out/deko3d_shaders/deko3d_shaders.bin"
if [[ ! -f "$cache" || "$root/out/deko3d_shaders/glsl_opt" -nt "$cache" ]]; then
  # One tiny uam process per variant and no big memory use, so not the (memory-bound) compile jobs of the game: every core.
  python3 -I "$root/tools/renut/precompile_all_variants.py" --jobs "${SHADER_JOBS:-$(nproc)}"
else
  echo "deko3d_shaders.bin is up to date"
fi

step "The SD card folder"
"$root/tools/package_switch.sh" --with-game

cat <<DONE

Done: $root/out/nx/sdcard/switch/alice-nx
Copy out/nx/sdcard/switch to the root of your Switch's SD card, then start the game from the homebrew menu opened
through a game (hold R while starting a game), not from the album. Everything in that folder is for your own console
only: never share it.
DONE
(( check == 0 )) || die "tools/check_switch_build.py failed (see out/check_switch_build.log); everything was still built"
