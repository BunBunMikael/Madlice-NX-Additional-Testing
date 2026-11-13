#!/usr/bin/env python3
"""alice-nx (2026-11-04): every deko3d shader variant the game can need, compiled on the PC into one DKSH cache.

    python3 -I tools/renut/precompile_all_variants.py [--glsl out/deko3d_shaders/glsl_opt]
        [--out out/deko3d_shaders/deko3d_shaders.bin] [--jobs 4] [--limit N] [--dry-run]

Why it can be complete. With the Switch defaults of app/src/alice_app.h (banjo_gpu_bool_spec, banjo_gpu_blend_skip,
banjo_gpu_output_trim and banjo_deko3d_vs_outputs off; banjo_deko3d_alpha_spec off by default), the only
specialization constants Build() (render/pipeline.cpp) and plume_deko3d's createGraphicsPipeline still give a shader
are:
  - 904 = 1 for the vertex shader of every pipeline that is not a tessellated draw's (banjo_deko3d_tess_spec), none
    for a tessellated one;
  - 909 = 1 for the pixel shader of a draw that writes neither depth nor stencil (banjo_deko3d_early_z), none
    otherwise.
(907, 908, 910-912 are set only in non-default modes or for banjo-nx's listed shaders.) So each vertex shader has at
most the variants {} and {904: 1}, each pixel shader {} and {909: 1}, and a constant a shader's GLSL does not declare
makes no define. The text and key are tools/renut/deko3d_variant_cache.py's (plume's loadVariant): the defines whose
value differs from the GLSL's default after the first line, FNV-1a 64 of the whole text. The console reads the cache
next to the NRO (deko3d_shaders.bin, banjo_renut_deko3d.cpp LoadCache) and compiles only what is not in it.

Game data: the file goes to the build tree and the player's SD card only.
"""
import argparse
import concurrent.futures
import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
spec = importlib.util.spec_from_file_location('dvc', os.path.join(HERE, 'deko3d_variant_cache.py'))
dvc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dvc)

VARIANTS = {'vs': [{}, {904: 1}], 'ps': [{}, {909: 1}]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--glsl', default=os.path.join(ROOT, 'out', 'deko3d_shaders', 'glsl_opt'))
    ap.add_argument('--out', default=os.path.join(ROOT, 'out', 'deko3d_shaders', 'deko3d_shaders.bin'))
    ap.add_argument('--jobs', type=int, default=max(1, (os.cpu_count() or 4)))
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    if not os.path.exists(dvc.UAM):
        sys.exit(f'precompile_all_variants: no uam at {dvc.UAM} (tools/deko3d_build_tools.sh)')

    items = {}
    names = sorted(n for n in os.listdir(a.glsl) if n.endswith('.glsl'))
    if a.limit:
        names = names[:a.limit]
    for name in names:
        prefix = name[:2]
        if prefix not in VARIANTS:
            continue
        glsl = open(os.path.join(a.glsl, name), 'rb').read().decode('utf-8')
        defaults = dvc.spec_defaults(glsl)
        stage = 'vert' if prefix == 'vs' else 'frag'
        for values in VARIANTS[prefix]:
            defines = dvc.variant_defines(defaults, values)
            if values and not defines:
                continue  # the shader does not declare the constant: the same text as the default variant
            text = dvc.variant_text(glsl, defines).encode('utf-8')
            key = dvc.fnv1a64(text)
            items.setdefault(key, (key, stage, text))
    print(f'precompile_all_variants: {len(names)} shaders, {len(items)} variants')
    if a.dry_run:
        return

    done = 0
    failed = []
    records = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
        for key, dksh, log in pool.map(dvc.compile_one, items.values(), chunksize=16):
            done += 1
            if dksh is None:
                failed.append((key, log))
            else:
                records.append((key, dksh))
            if done % 2000 == 0:
                print(f'  {done} of {len(items)} ({len(failed)} failed)', flush=True)
    records.sort()
    tmp = a.out + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(b'BDKC' + struct.pack('<I', 1) + dvc.TAG)
        for key, dksh in records:
            f.write(struct.pack('<QI', key, len(dksh)))
            f.write(dksh)
    os.replace(tmp, a.out)
    size = os.path.getsize(a.out)
    print(f'precompile_all_variants: {len(records)} variants, {len(failed)} failed, {size / 2**20:.1f} MB -> {a.out}')
    for key, log in failed[:10]:
        print(f'  failed {key:016X}: {log}')


if __name__ == '__main__':
    main()
