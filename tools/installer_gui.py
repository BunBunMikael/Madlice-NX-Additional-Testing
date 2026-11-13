#!/usr/bin/env python3
"""The builder window, for Linux and Windows: pick your own game disc, build the port, copy it to the SD card.

    Linux:    python3 tools/installer_gui.py
    Windows:  double-click installer_gui.py (or: py installer_gui.py). Needs WSL2 with a Linux distro (Ubuntu):
              run "wsl --install" in PowerShell once. The build runs inside WSL, in ~/alice-nx there.

It runs tools/build_from_disc.sh: the port is built from YOUR copy of the game, on this PC. Nothing is downloaded but
the open-source tools. Linux needs Python 3 with Tk (Arch: tk; Debian/Ubuntu: python3-tk; Fedora: python3-tkinter);
the Python from python.org on Windows has it. "Check requirements" lists what else is missing.
"""
import os
import queue
import re
import shlex
import shutil
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

WINDOWS = os.name == "nt"
REPO_URL = "https://github.com/adumah/alice-nx.git"
HERE = Path(__file__).resolve().parent.parent  # the repo (Linux)
ANSI = re.compile(r"\x1b\[[0-9;]*m")
STEP = re.compile(r"^== (.*)$")
# The steps build_from_disc.sh prints, in order (for the progress bar).
STEPS = [
    "Checking the tools", "Your game", "sa2-nx", "The code generator", "Translating", "Every shader from",
    "The shaders, translated", "The game's shaders for the Switch", "Every shader variant", "The Switch build",
    "The SD card folder",
]
NO_WINDOW = 0x08000000 if WINDOWS else 0  # CREATE_NO_WINDOW: no console window flashing up for each wsl.exe call

# Runs in bash (here, or inside WSL): prints what is missing and how to install it on this distro.
CHECK = r'''
missing=(); for t in clang cmake ninja python3 git; do command -v "$t" >/dev/null || missing+=("$t"); done
dkp="${DEVKITPRO:-/opt/devkitpro}"
id=""; [ -r /etc/os-release ] && . /etc/os-release && id="$ID $ID_LIKE"
free_gb=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
echo "Linux: ${PRETTY_NAME:-unknown}, ${free_gb} GB of memory, $(nproc) CPU threads"
[ "$free_gb" -ge 10 ] || echo "  less than 10 GB of memory: use 1-2 compile jobs"
if [ ${#missing[@]} -eq 0 ]; then echo "OK: clang, cmake, ninja, python3, git"
else
  echo "missing: ${missing[*]}"
  case "$id" in
    *arch*) echo "  install: sudo pacman -S --needed clang cmake ninja python git libx11 libxcb wayland" ;;
    *fedora*|*rhel*) echo "  install: sudo dnf install clang cmake ninja-build python3 git libX11-devel libxcb-devel wayland-devel" ;;
    *debian*|*ubuntu*) echo "  install: sudo apt install clang cmake ninja-build python3 git libx11-dev libxcb1-dev libwayland-dev" ;;
    *) echo "  install clang, cmake 3.25+, ninja, python3, git and the X11/XCB/Wayland development files" ;;
  esac
fi
v=$(cmake --version 2>/dev/null | awk 'NR==1 {print $3}')
[ -z "$v" ] || [ "$(printf '%s\n3.25\n' "$v" | sort -V | head -1)" = 3.25 ] || echo "cmake $v is too old: 3.25 or newer is needed"
if [ -x "$dkp/devkitA64/bin/aarch64-none-elf-gcc" ]; then echo "OK: devkitPro at $dkp"
else
  echo "missing: devkitPro (devkitA64, libnx, deko3d, switch-tools) at $dkp"
  echo "  see https://devkitpro.org/wiki/Getting_Started, then: sudo dkp-pacman -S switch-dev deko3d"
  echo "  (on Arch the command is: sudo pacman -S switch-dev deko3d)"
fi
'''


TITLE_ID, MEDIA_ID = 0x45410916, 0x31C4B45C  # Alice: Madness Returns, the disc this port's corrections are for


def disc_problem(game):
    """(ok, message) for a picked disc folder or .iso."""
    if not game:
        return False, "Nothing chosen yet."
    p = Path(game)
    if not p.exists():
        return False, f"{p} does not exist."
    if p.is_file():
        if p.stat().st_size < 1 << 30:
            return False, "This file is too small for an Xbox 360 disc image."
        return True, "Disc image chosen: it is checked when the build extracts it."
    xex = next((p / n for n in ("Default.xex", "default.xex") if (p / n).is_file()), None)
    if not xex:
        return False, f"There is no Default.xex in {p}: choose the folder you extracted the disc into."
    import struct
    try:
        head = xex.open("rb").read(64 * 1024)
        if head[:4] != b"XEX2":
            return False, "Default.xex is not an Xbox 360 executable."
        for i in range(struct.unpack(">I", head[0x14:0x18])[0]):
            key, val = struct.unpack(">II", head[0x18 + 8 * i:0x20 + 8 * i])
            if key == 0x00040006:  # execution info: media ID, version, base version, title ID
                media, version, _, title = struct.unpack(">IIII", head[val:val + 16])
                break
        else:
            return False, "Default.xex has no title ID."
    except (OSError, struct.error) as e:
        return False, f"Could not read Default.xex: {e}"
    if title != TITLE_ID:
        return False, f"This is another game (title ID {title:08X}); Alice: Madness Returns is {TITLE_ID:08X}."
    if media != MEDIA_ID:
        return False, (f"Alice: Madness Returns, but another release (media ID {media:08X}; this port was made "
                       f"for {MEDIA_ID:08X}). It may not work.")
    if not (p / "Content").exists() and not any(p.glob("*/")):
        return False, "Default.xex is there, but the game's other files are missing: extract the whole disc."
    return True, f"Alice: Madness Returns (title ID {title:08X}, media ID {media:08X}, version {version}): OK."


class Runner:
    """Runs bash commands here (Linux) or inside WSL (Windows), in the repo."""

    def __init__(self):
        self.repo = "~/alice-nx" if WINDOWS else str(HERE)

    def argv(self, script):
        if WINDOWS:
            return ["wsl.exe", "-e", "bash", "-lc", script]
        return ["bash", "-c", script]

    def run(self, script, timeout=None):
        r = subprocess.run(self.argv(script), capture_output=True, text=True, timeout=timeout,
                           creationflags=NO_WINDOW, encoding="utf-8", errors="replace")
        return r.returncode, (r.stdout + r.stderr).strip()

    def popen(self, script):
        return subprocess.Popen(self.argv(script), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                bufsize=1, creationflags=NO_WINDOW, encoding="utf-8", errors="replace",
                                start_new_session=not WINDOWS)

    def linux_path(self, path):
        """A path the build can open: C:\\x -> /mnt/c/x inside WSL."""
        if not WINDOWS:
            return path
        code, out = self.run(f"wslpath -a {shlex.quote(path.replace(chr(92), '/'))}")
        if code:
            raise RuntimeError(f"wslpath: {out}")
        return out.splitlines()[-1]

    def result_dir(self):
        """The built SD card folder, as this OS sees it."""
        if not WINDOWS:
            return HERE / "out" / "nx" / "sdcard" / "switch" / "alice-nx"
        code, out = self.run(f"wslpath -w {self.repo}/out/nx/sdcard/switch/alice-nx")
        return Path(out.splitlines()[-1]) if code == 0 and out else None

    def wsl_problem(self):
        if not WINDOWS:
            return None
        if not shutil.which("wsl.exe"):
            return "WSL is not installed. Open PowerShell as administrator, run:  wsl --install  and restart."
        try:
            code, out = self.run("echo ok", timeout=120)
        except subprocess.TimeoutExpired:
            return "WSL did not answer. Open Ubuntu from the Start menu once to finish its setup."
        if code or "ok" not in out:
            return ("WSL has no Linux distro yet. In PowerShell run:  wsl --install -d Ubuntu  then open Ubuntu "
                    "once to make your user.\n\n" + out)
        return None


class Installer(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Alice: Madness Returns for Switch - builder")
        self.geometry("880x760")
        self.minsize(660, 480)
        self.runner = Runner()
        self.proc = None
        self.lines = queue.Queue()

        self.game = tk.StringVar()
        self.devkitpro = tk.StringVar(value="/opt/devkitpro" if WINDOWS else os.environ.get("DEVKITPRO", "/opt/devkitpro"))
        self.jobs = tk.IntVar(value=4)
        self.sdcard = tk.StringVar()
        self.status = tk.StringVar(value="Pick your own game disc (an extracted folder or an .iso), then Build.")

        self.mode = tk.StringVar(value="full")
        self.disc_info = tk.StringVar(value="Nothing chosen yet.")

        pad = {"padx": 8, "pady": 4}

        def step(title):
            box = ttk.LabelFrame(self, text=title)
            box.pack(fill="x", padx=8, pady=(6, 2))
            box.columnconfigure(1, weight=1)
            return box

        def row(box, r, label, var, buttons):
            ttk.Label(box, text=label).grid(row=r, column=0, sticky="w", **pad)
            ttk.Entry(box, textvariable=var).grid(row=r, column=1, sticky="ew", **pad)
            bb = ttk.Frame(box)
            bb.grid(row=r, column=2, sticky="e")
            for text, cmd in buttons:
                ttk.Button(bb, text=text, command=cmd).pack(side="left", padx=2)

        # 1. Your game
        s1 = step(" 1. Choose your game ")
        row(s1, 0, "Your game disc", self.game, [("Folder...", self.pick_folder), ("ISO...", self.pick_iso)])
        self.disc_label = ttk.Label(s1, textvariable=self.disc_info)
        self.disc_label.grid(row=1, column=1, columnspan=2, sticky="w", **pad)

        # 2. Build
        s2 = step(" 2. Build the port on this PC (a few hours the first time) ")
        row(s2, 0, "devkitPro" + (" (in WSL)" if WINDOWS else ""), self.devkitpro,
            [] if WINDOWS else [("Browse...", lambda: self.pick_dir(self.devkitpro))])
        ttk.Label(s2, text="Compile jobs").grid(row=1, column=0, sticky="w", **pad)
        jobs = ttk.Frame(s2)
        jobs.grid(row=1, column=1, columnspan=2, sticky="w", **pad)
        ttk.Spinbox(jobs, from_=1, to=max(1, os.cpu_count() or 4), textvariable=self.jobs, width=4).pack(side="left")
        ttk.Label(jobs, text="  about 2.5 GB of memory each; 4 needs about 10 GB").pack(side="left")
        b2 = ttk.Frame(s2)
        b2.grid(row=2, column=0, columnspan=3, sticky="w", **pad)
        self.check_btn = ttk.Button(b2, text="Check requirements", command=self.check)
        self.check_btn.pack(side="left")
        self.build_btn = ttk.Button(b2, text="Build", command=self.start)
        self.build_btn.pack(side="left", padx=4)
        self.stop_btn = ttk.Button(b2, text="Stop", command=self.stop, state="disabled")
        self.stop_btn.pack(side="left", padx=4)

        # 3. SD card
        s3 = step(" 3. Copy it to the Switch's SD card ")
        row(s3, 0, "SD card", self.sdcard, [("Browse...", lambda: self.pick_dir(self.sdcard))])
        b3 = ttk.Frame(s3)
        b3.grid(row=1, column=0, columnspan=3, sticky="w", **pad)
        ttk.Radiobutton(b3, text="First install (everything, about 5 GB)", variable=self.mode,
                        value="full").pack(side="left")
        ttk.Radiobutton(b3, text="Update (only the game and its shaders; game_root is kept)", variable=self.mode,
                        value="update").pack(side="left", padx=8)
        b4 = ttk.Frame(s3)
        b4.grid(row=2, column=0, columnspan=3, sticky="w", **pad)
        self.copy_btn = ttk.Button(b4, text="Copy to SD card", command=self.copy_to_sd)
        self.copy_btn.pack(side="left")
        ttk.Button(b4, text="Open result folder", command=self.open_result).pack(side="left", padx=4)
        ttk.Label(s3, foreground="#777", wraplength=800, text=(
            "Then start the game from the homebrew menu opened through a game (hold R while starting a game), "
            "not from the album: the album does not give it enough memory.")).grid(
            row=3, column=0, columnspan=3, sticky="w", **pad)

        self.bar = ttk.Progressbar(self, maximum=len(STEPS))
        self.bar.pack(fill="x", **pad)
        ttk.Label(self, textvariable=self.status, wraplength=820).pack(anchor="w", **pad)

        logbox = ttk.Frame(self)
        logbox.pack(fill="both", expand=True, **pad)
        mono = ("Consolas" if WINDOWS else "monospace", 9)
        self.log = tk.Text(logbox, wrap="none", height=10, font=mono, state="disabled")
        scroll = ttk.Scrollbar(logbox, command=self.log.yview)
        self.log.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        self.log.pack(side="left", fill="both", expand=True)
        self.log.tag_configure("step", foreground="#a0409f", font=mono + ("bold",))
        self.log.tag_configure("error", foreground="#c03030")

        ttk.Label(self, foreground="#777", wraplength=820, text=(
            "This builds the port from your own copy of the game, on this PC, and takes a few hours. The result "
            "contains the game's code and shaders: it is for your own console only. Never share it.")).pack(
            anchor="w", **pad)

        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.after(100, self.pump)

    # ---- pickers
    def pick_folder(self):
        d = filedialog.askdirectory(title="Your extracted disc (the folder with Default.xex)")
        if d:
            self.game.set(d)
            self.check_disc()

    def pick_iso(self):
        f = filedialog.askopenfilename(title="Your disc image", filetypes=[("Disc image", "*.iso"), ("All", "*")])
        if f:
            self.game.set(f)
            self.check_disc()

    def pick_dir(self, var):
        d = filedialog.askdirectory()
        if d:
            var.set(d)

    # ---- the disc check
    def check_disc(self):
        """Is it the disc this port was made for? Reads Default.xex's header: seconds now, not hours into a build."""
        ok, msg = disc_problem(self.game.get().strip())
        self.disc_info.set(msg)
        self.disc_label.configure(foreground="#2a8a2a" if ok else "#c03030")
        return ok

    # ---- log
    def append(self, text, tag=None):
        self.log.configure(state="normal")
        self.log.insert("end", text if text.endswith("\n") else text + "\n", tag)
        self.log.see("end")
        self.log.configure(state="disabled")

    def clear(self):
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")

    def busy(self, on):
        for b in (self.check_btn, self.build_btn, self.copy_btn):
            b["state"] = "disabled" if on else "normal"
        self.stop_btn["state"] = "normal" if on and self.proc else "disabled"

    def background(self, work, done):
        """work() runs off the UI thread; done(result) runs on it."""
        def go():
            try:
                res = work()
            except Exception as e:  # noqa: BLE001 - shown to the user
                res = e
            self.lines.put(("call", done, res))  # Tk may only be touched from its own thread: pump() runs it
        threading.Thread(target=go, daemon=True).start()

    # ---- requirements
    def check(self):
        self.clear()
        self.busy(True)
        self.status.set("Checking...")
        dkp = self.devkitpro.get().strip() or "/opt/devkitpro"

        def work():
            problem = self.runner.wsl_problem()
            if problem:
                return problem
            _, out = self.runner.run(f"export DEVKITPRO={shlex.quote(dkp)}\n" + CHECK)
            return out

        def done(out):
            self.busy(False)
            self.append(str(out))
            self.status.set("Install what is missing, then press Build." if "missing" in str(out) or
                            "WSL" in str(out) else "Everything needed is there.")

        self.background(work, done)

    # ---- build
    def start(self):
        game = self.game.get().strip()
        if game and not self.check_disc():
            messagebox.showerror("Your game", self.disc_info.get())
            return
        self.clear()
        self.bar["value"] = 0
        self.busy(True)
        self.status.set("Starting...")
        dkp = self.devkitpro.get().strip() or "/opt/devkitpro"
        jobs = max(1, self.jobs.get())

        def work():
            problem = self.runner.wsl_problem()
            if problem:
                raise RuntimeError(problem)
            repo = self.runner.repo
            lines = [f"export DEVKITPRO={shlex.quote(dkp)}"]
            if WINDOWS:  # the build lives in WSL's own disk: much faster than /mnt/c, and links work there
                lines.append(f"[ -d {repo}/.git ] || git clone {REPO_URL} {repo} || exit 1")
            lines.append(f"cd {repo} || exit 1")
            args = ["--jobs", str(jobs)]
            if game:
                args.append(self.runner.linux_path(game))
            # Own process group (setsid), its id in a file: Stop can end every compiler, also inside WSL.
            lines.append("echo $$ > ~/.alice-build.pid")
            lines.append("exec tools/build_from_disc.sh " + " ".join(shlex.quote(a) for a in args))
            script = "\n".join(lines)
            return self.runner.popen(f"exec setsid -w bash -c {shlex.quote(script)}")

        def done(proc):
            if isinstance(proc, Exception):
                self.busy(False)
                self.status.set("Could not start.")
                messagebox.showerror("Could not start", str(proc))
                return
            self.proc = proc
            self.busy(True)
            self.status.set("Building... (a few hours; you can leave it running)")
            threading.Thread(target=self.reader, args=(proc,), daemon=True).start()

        self.background(work, done)

    def reader(self, proc):
        for line in proc.stdout:
            self.lines.put(ANSI.sub("", line))
        self.lines.put(("done", proc.wait()))

    def pump(self):
        try:
            while True:
                item = self.lines.get_nowait()
                if isinstance(item, tuple):
                    if item[0] == "call":
                        item[1](item[2])
                    else:
                        self.finished(item[1])
                    continue
                m = STEP.match(item.strip())
                if m:
                    name = m.group(1)
                    for i, s in enumerate(STEPS):
                        if name.startswith(s):
                            self.bar["value"] = i
                    self.status.set(f"Step {int(self.bar['value']) + 1}/{len(STEPS)}: {name}")
                    self.append(item, "step")
                else:
                    self.append(item, "error" if re.search(r"\b(error|missing|FAILED)\b", item) else None)
        except queue.Empty:
            pass
        self.after(100, self.pump)

    def finished(self, code):
        self.proc = None
        self.busy(False)
        if code == 0:
            self.bar["value"] = len(STEPS)
            self.status.set("Done: the SD card folder is ready.")
            if self.sdcard.get().strip():
                self.copy_to_sd()
            else:
                messagebox.showinfo("Done", "The build is ready. Pick your SD card and press \"Copy to SD card\".")
        else:
            self.status.set(f"Stopped (code {code}). Fix what the log says and press Build again: finished steps "
                            "are skipped.")

    def kill_build(self):
        # The whole process group: the script and every compiler it started.
        self.runner.run("kill -TERM -- -$(cat ~/.alice-build.pid) 2>/dev/null; rm -f ~/.alice-build.pid")

    def stop(self):
        if self.proc and messagebox.askyesno("Stop", "Stop the build? Finished steps are kept."):
            self.kill_build()

    # ---- result
    def copy_to_sd(self):
        sd = self.sdcard.get().strip() or filedialog.askdirectory(title="Your SD card's root")
        if not sd:
            return
        self.sdcard.set(sd)
        self.busy(True)
        update = self.mode.get() == "update"
        self.status.set("Updating the game on the SD card..." if update else "Copying to the SD card (about 5 GB)...")

        def work():
            src = self.runner.result_dir()
            if not src or not Path(src).is_dir():
                raise RuntimeError("Nothing to copy yet: build first.")
            dst = Path(sd) / "switch" / "alice-nx"
            keep = (dst / "alice.toml").read_bytes() if (dst / "alice.toml").exists() else None
            if update:
                if not (dst / "game_root").is_dir():
                    raise RuntimeError(f"No game_root in {dst} yet: choose First install.")
                dst.mkdir(parents=True, exist_ok=True)
                for name in ("alice.nro", "deko3d_shaders.bin"):
                    if (Path(src) / name).exists():
                        shutil.copy2(Path(src) / name, dst / name)
            else:
                # Real files, not links (game_root may link to your disc folder); your own alice.toml is kept.
                shutil.copytree(src, dst, dirs_exist_ok=True, symlinks=False)
            if keep is not None:
                (dst / "alice.toml").write_bytes(keep)
            if not WINDOWS:
                subprocess.run(["sync"])
            return dst

        def done(res):
            self.busy(False)
            if isinstance(res, Exception):
                self.status.set(f"Copy failed: {res}")
                messagebox.showerror("SD card", f"Copy failed: {res}")
                return
            msg = (f"Copied to {res}. Eject the card safely, then start the game from the homebrew menu opened "
                   "through a game (hold R while starting a game), not from the album.")
            self.status.set(msg)
            messagebox.showinfo("SD card", msg)

        self.background(work, done)

    def open_result(self):
        target = self.runner.result_dir()
        if not target or not Path(target).is_dir():
            messagebox.showinfo("Result", "Nothing built yet.")
        elif WINDOWS:
            os.startfile(target)  # noqa: S606 - opens Explorer
        elif shutil.which("xdg-open"):
            subprocess.Popen(["xdg-open", str(target)])

    def on_close(self):
        if self.proc:
            if not messagebox.askyesno("Quit", "A build is running. Stop it and quit?"):
                return
            self.kill_build()
        self.destroy()


if __name__ == "__main__":
    Installer().mainloop()
