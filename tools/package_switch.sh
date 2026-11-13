#!/usr/bin/env bash
# The SD card folder of the Switch build (sa2-nx's tools/win/package_switch.ps1, for Linux):
#   out/nx/sdcard/switch/alice-nx/alice.nro
#   out/nx/sdcard/switch/alice-nx/deko3d_shaders.bin   every shader variant, compiled on the PC
#                                                     (tools/renut/precompile_all_variants.py): no compiles while playing
#   out/nx/sdcard/switch/alice-nx/game_root/          with --with-game: a copy of your game files (assets/game_root)
# Copy out/nx/sdcard/switch to the card's root (it merges with the card's switch folder). The game reads game_root/
# as it is (4.5 GB: too large for one packed file on FAT32). Logs go to logs/ in the same folder.
#
# Everything in this folder is for your own console only: the NRO holds the game's translated code and shaders, the
# cache its shaders, and game_root is your copy of the game. Never share any of them.
#
#   tools/package_switch.sh [--with-game]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
nro="$root/out/nx/alice.nro"
dest="$root/out/nx/sdcard/switch/alice-nx"
[[ -f "$nro" ]] || { echo "no $nro: run tools/build_switch.sh first" >&2; exit 1; }
mkdir -p "$dest"
cp "$nro" "$dest/alice.nro"
cache="$root/out/deko3d_shaders/deko3d_shaders.bin"
if [[ -f "$cache" ]]; then
  cp "$cache" "$dest/deko3d_shaders.bin"
else
  echo "warning: no $cache (tools/renut/precompile_all_variants.py): the console will compile shaders while playing" >&2
fi
if [[ "${1:-}" == "--with-game" ]]; then
  [[ -f "$root/assets/game_root/Default.xex" ]] || { echo "no assets/game_root/Default.xex" >&2; exit 1; }
  rm -rf "$dest/game_root"
  cp -rL "$root/assets/game_root" "$dest/game_root"
fi
du -sh "$dest"
find "$root/out/nx/sdcard" -maxdepth 3 | sed "s|$root/out/nx/||"
