#!/usr/bin/env python3
"""After every codegen: app/generated/codegen_flavor.txt, the codegen flavour's name in the first "[enh]" log line.

Run by tools/codegen.sh and by the PC build itself (app/CMakeLists.txt appends this script to the generator's command,
which the build re-runs on its own when an input changes).

The flavour is app/codegen_flavor.toml (included by app/alice_manifest.toml): "classic" when it sets no key, otherwise
"optimised: " and its keys. The file is written only when its text changes, so the build does not reconfigure for
nothing.

alice-nx (2026-11-05): the post-codegen rewrites of sa2-nx's optimised flavour (no-volatile pch, loop barriers, direct
calls) and its stage B options (non_volatile_as_local, elide_lr_stores) glitched Alice's textures on the console in
every combination tried (docs/alice-notes.md, 2026-11-03/04); they were removed from this repository. sa2-nx keeps the
tools.

  python3 tools/post_codegen.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, 'app')
GEN = os.path.join(APP, 'generated')


def main():
    flavor_toml = open(os.path.join(APP, 'codegen_flavor.toml'), encoding='utf-8').read()
    keys = re.findall(r'^\s*([a-z_]+)\s*=\s*true', flavor_toml, re.M)
    text = 'optimised: ' + ', '.join(keys) if keys else 'classic'
    path = os.path.join(GEN, 'codegen_flavor.txt')
    try:
        old_text = open(path, encoding='utf-8').read()
    except OSError:
        old_text = None
    if old_text != text:
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
    print(f'post_codegen: flavour "{text}"')


if __name__ == '__main__':
    main()
