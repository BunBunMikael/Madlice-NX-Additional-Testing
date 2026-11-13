# Build and test notes for the Switch CPU / texture optimization pass

This is a source-only update. It does not include game files, generated game code, shader payloads, an NRO, or the external ReXGlue SDK checkout.

## Required build inputs

Follow the existing `README.md` build instructions. In particular, place the required `sa2-nx` checkout next to this repository at the commit documented there, install devkitPro/devkitA64 and the listed host dependencies, and build from your own legally dumped game files.

## Four-core launch

Create a Sphaira forwarder for the built NRO and configure it for four CPU cores. Core 3 is not made available by an application-side affinity setting; it must be in the process's allowed core mask. The texture worker tries to pin to core 3 and falls back to serial conversion if the kernel rejects the pin. The denial is cached for the process lifetime to avoid repeatedly creating a worker that cannot run there.

## Runtime A/B tests

- Compare the same scene with `banjo_texture_worker_core = 3` and `banjo_texture_worker_core = -1`.
- Record average FPS and frame-time percentiles, not just peak FPS.
- Watch for texture upload stalls, audio glitches, and HOME-menu/overlay responsiveness.
- Confirm that high-detail textures update correctly and that no stale or corrupted textures appear.
- Compare a three-core launch against a four-core Sphaira forwarder.

The worker only parallelizes large deferred texture batches (at least 1 MiB and two or more fills). It reads guest memory at the renderer's existing flush boundary, writes only to the corresponding staging allocations, and joins before command submission can consume those allocations. Texture formats, dimensions, mip levels, filtering, and render-target quality are unchanged.

## Validation status

The source-level checks and Python tool syntax checks can be run without a Switch SDK. A full Switch build and hardware test were not possible in the preparation environment because devkitPro/devkitA64 and the required adjacent `sa2-nx` SDK checkout were not present. Do not treat this archive as a prebuilt or hardware-validated release.
