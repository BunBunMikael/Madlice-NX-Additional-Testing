#!/usr/bin/env bash
# Sends out/nx/alice.nro to a Switch waiting in the Homebrew Menu's netloader (Y), then prints the game's log here.
# Log: out/nxlink.log.
#
# The game files go on the SD card at sdmc:/switch/alice-nx/game_root/ (the disc folder holding Default.xex), next to
# the NRO. nxlink saves the NRO only into a folder that already exists ("open err=2" otherwise).
#
#   tools/send_switch.sh [switch-ip] [-- extra game options]
# Without an address, nxlink finds the Switch by broadcast. The game sends its log to this PC through --log_network
# (nxlink -s listens on port 28771).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
nxlink="${DEVKITPRO:-/opt/devkitpro}/tools/bin/nxlink"
addr=()
if [[ $# -gt 0 && "$1" != "--" ]]; then addr=(-a "$1"); shift; fi
[[ "${1:-}" == "--" ]] && shift
# This PC's address on the route to the Switch's network, for the game's log connection.
host="$(ip -4 route get "${addr[1]:-192.168.0.1}" | sed -n 's/.* src \([0-9.]*\).*/\1/p')"
mkdir -p "$root/out"
# stdbuf: nxlink's output into a pipe is otherwise held back in blocks of 4 KB, so the log would lag by minutes.
stdbuf -oL -eL "$nxlink" "${addr[@]}" -p alice-nx/alice.nro -s -- "$root/out/nx/alice.nro" --log_network="$host:28771" "$@" \
  2>&1 | tee "$root/out/nxlink.log"
