# Switch texture-path changes

This patch keeps guest texture dimensions, formats, mip levels, filtering, and render-target
quality unchanged.

## Changes

- `sa2_compat.cpp`: allow the background compile and render-ring affinity settings to select core 3 when the title was launched with a four-core process mask (for example, a Sphaira four-core forwarder). The render thread remains on core 1 and background compilation remains on core 2; the new texture worker defaults to core 3. If core 3 is not in the process mask, the pin operation fails safely and the worker remains schedulable on its inherited mask.
- `banjo_renut_record.cpp`: allow the deferred command-recording worker to be pinned to core 3, defaulting there when available.
- `render/textures.cpp`: deferred texture fills now use a bounded, temporary two-way conversion split for batches of at least 1 MiB. The render thread converts one half while a helper converts the other half on the configured worker core. The helper reads guest memory only at the existing flush boundary, uses thread-local row scratch, and does no GPU work. If core 3 is unavailable or thread creation fails, conversion falls back to serial processing.

- `render/format.cpp`: use ARM Advanced SIMD (NEON) to perform Xenos 8-in-16,
  8-in-32, and 16-in-32 byte swaps in 16-byte vectors. The existing scalar
  implementation remains the fallback and handles the tail.
- `render/textures.cpp`: reuse the renderer-thread row scratch buffer across
  texture subresources. This removes repeated temporary-vector allocations while
  untile/copy/endian-convert work is performed for mip levels and array slices.

## Four-core launch and affinity

Launch the NRO through a Sphaira-generated forwarder configured for four CPU cores. The application cannot grant itself access to core 3: the forwarder must provide the process capability/mask. At startup, check the log messages from `OnBackgroundThreadStart` and the recording worker for an accepted core pin. A failed pin is not proof that the code is broken; it usually means the process was not launched with core 3 available. Core 3 is also used by Horizon services, so keep the worker set bounded and benchmark system responsiveness.

The existing guest-thread layout remains cores 0-2 (`RexSetGuestThreadCoreLayout(0, 0x6, 2)`). This deliberately leaves core 3 for the texture helper instead of allowing all guest threads to contend for it. Pipeline compilation and the render thread retain their existing core assignments.

## Texture residency / blurry-to-sharp behaviour

The renderer creates host textures from the guest fetch constant and its declared
mip chain. It does not intentionally substitute lower-resolution source assets.
A game that first submits a low-detail asset and later streams a high-detail asset
will still show the low-detail asset until the guest memory/header changes.

For a persistent low-detail image, capture the affected texture's guest address,
dimensions, format, mip range, and the frames on which its content hash changes.
That distinguishes game-side LOD/streaming decisions from a renderer refresh or
mip-selection problem. The current tiled-texture fingerprint samples the texture
extent unless guest-store cards are enabled; if a writer bypasses the card marking
path, a sparse fingerprint can miss a change outside its probes. Do not globally
increase texture resolution or force mip bias as a workaround: that changes
quality/performance semantics and may not address asset streaming.

## Current limits / next profiling step

The deferred `PendingFill` list remains synchronized at the existing flush boundary. Large batches are split between the render thread and one temporary worker; this avoids a persistent worker lifecycle and keeps staging destinations alive until the worker joins. The 1 MiB threshold is a conservative starting point and should be tuned from real-device timings. If it does not improve frame-time variance, disable it with `banjo_texture_worker_core = -1`.

## Validation

The scalar endian routine was compiled and checked for all four endian modes,
in-place and out-of-place, over complete 32-bit word lengths. The NEON intrinsic
sequence was syntax-checked for AArch64/ARMv8-A. A full Switch build and on-device
visual/performance test remain required; this source archive does not include the
SDK-generated tree or third-party dependency checkout needed for that build.
