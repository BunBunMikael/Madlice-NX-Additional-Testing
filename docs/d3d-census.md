# Direct3D census (for the native renderer)

The Switch build needs a native renderer, so the game's XDK Direct3D functions have to be hooked, and the device's
state read at known offsets. This file records which function is which in Alice: Madness Returns' `Default.xex`, and
why. As sa2-nx's guide asks, it names the source of every one. Monster High's values (mhnwis-nx, XDK 2.0.21256) are
given for comparison.

Tools:
- `tools/d3d/fnindex.py build|show|callers|grep`: listings and the call graph from the generated code.
- `tools/d3d/fingerprint.py`: functions using a set of displacements.
- `tools/d3d/census_build.py` / `census_report.py`: a diagnostic build counting every call in a range.

Static analysis done 2026-11-02. The runtime census is still to come.

## The library

Alice links XDK 2.0.20353 with **D3D9LTCG**. The Direct3D library is link-time optimised together with the game, so
some XDK functions are inlined or take different arguments than in SA2 or Monster High. For example, game code calls
the resolve worker directly. The library's code sits at 0x82B40000-0x82B80000, and the game's own D3D layer (Unreal's
Xenon renderer) sits right below it at 0x82A4xxxx-0x82A5xxxx.

## The device layout differs from Monster High's

The device is 0x5F80 bytes, against Monster High's 0x6080. Fields after about +11100 sit 128 bytes lower; the ring
and fence fields are unchanged.

| What | Monster High | Alice | Evidence |
|---|---|---|---|
| Device allocation, clear | 0x6080 at 0x80 | 24576 allocated, aligned to 128 (`addi 131` / mask), 24448 (0x5F80) cleared | CreateDevice `sub_82B5C288` |
| Global device pointer | | 0x8335016C | CreateDevice: `stw r31,364(r30)` with r30 = 0x83350000 |
| Ring, ring limit, ring guarantee | +48, +52, +56 | same | BeginRingBig compares +48 + 4n with +52; KickOff returns +48; `sub_82B58340` tests +48 against +56 |
| Fence completion pointer, fence tag | +11024, +11036 | same | KickOff, BlockOnFence `tag - fence < tag - *completion` |
| Flag bytes | +11068..+11071 | same (+11068, +11069 read; +11072 in the draws) | KickOff, the segment allocator, the draws |
| In KickOff | +13600 | **+13472** | KickOff, BlockOnFence, KickOffSegment's helper |
| Command buffer being recorded | +13920 | **+13792** | AllocateInlineData, the segment allocator |
| End of inline vertices | +13844 | **+13716** | the two UP draws |
| Swap count | +16968 | **+16840** | Swap: `lwz r11,16840(r31)` / `addi 1` / `stw` |
| Index buffer | +12812 | **+12684** | DrawIndexedVertices (`lwz r24,12684(r31)`), not DrawVertices |
| Render targets [4], depth | +12816, +12832 | **+12688..+12700, +12704** | `sub_82B5D7E8` (22 callers) reads exactly these five |
| Vertex shader: container, physical part | +0x368, +0x20 | same | XGRegisterVertexShader `sub_82B54ED8` |

Assumed, but not yet checked: stream sources, textures, the vertex declaration and the bound VS/PS are Monster High's
offsets − 128 (+12708, +12792, +12112, +12944, +12940). Each one gets confirmed when the renderer reads it.

## Functions identified

| Function | Monster High | Alice | Evidence |
|---|---|---|---|
| Direct3D_CreateDevice | 8265E2D8 | **82B5C288** | Allocates the device (above). E_OUTOFMEMORY (0x8007000E) on failure. Stores 0x0C000001 at +24264. Hardware path `sub_82B66420` (VdInitializeEngines, VdSetGraphicsInterruptCallback). One caller, `sub_82A54980`. |
| CDevice::KickOff | 82673110 | **82B57E60** | 70 callers. Checks +13472 and flag 0x80 of +11068. Waits through BlockOnFence on tag − 2 (+11036). Sets 0x2 of +11069. Returns the ring (+48). |
| CDevice::KickOffSegment | 82672D88 | **82B57B80** | Called by KickOff. Calls the segment allocator and the segment packet writer `sub_82B57D08` (+13472, +13632). |
| CDevice::BeginRingBig | 826733B8 | **82B56A98** | (device, count): ring + 4·count > limit (+52) → KickOff, then the segment allocator. Returns the ring. |
| Ring segment allocator | 82671ED0 | **82B57228** | (device, dwords). Its callers are exactly BeginRingBig, KickOffSegment and Swap, as in Monster High. Uses +13792. |
| RingBufferDeviceAllocate | 826716D8 | **82B56E58** | AllocateInlineData calls it as (device, 1, &size, alignment). |
| CDevice::AllocateInlineData | 82671DE8 | **82B57088** | (device, dwords, alignment): bytes = 4·dwords, from the command buffer (+13792) or RingBufferDeviceAllocate. |
| CDevice::BlockOnFence | 82671A68 | **82B57F60** | (device, fence, type, no_kick): the pending test on +11024/+11036, then KickOff when the fence is the current one and +13472 is clear. |
| D3D::SynchronizeToPresentationInterval | 82663DB8 | **82B58B18** | The only small function setting the swap-pending flag (0x10 of +11069). Called by Swap. |
| D3DDevice_Swap | 82664278 | **82B59050** | The only caller of VdSwap. Increments +16840. Copies 24 bytes of scaler parameters from arg 2 + 28. |
| D3DDevice_DrawVertices | 826747A0 | **82B55D68** | Exactly 0x418 before DrawIndexedVertices, as in SA2 and Monster High. Same state flush (`sub_82B5A258`, `82B5B2A8`, `82B59B28` …) without the index buffer. Called by Unreal's `sub_82A52870`. |
| D3DDevice_DrawIndexedVertices | 82674BB8 | **82B56180** | Reads the index buffer (+12684), then the draw packets. Called by Unreal's `sub_82A52908`. |
| D3DDevice_DrawVerticesUP | 82674178 | **82B55368** | count × stride is `r5 × r6`, and stride / 4 goes to the byte at +12776 (StreamStrides, confirmed). **LTCG changed the argument order**: the stride arrives in r6, where the XDK's (device, type, count, data, stride) puts it in r7, so Renut's hook needs rewriting, not just a new address. Census: 1 a frame, 8+ game callers. |
| D3DDevice_DrawIndexedVerticesUP | | **82B55828** | Seven arguments (r4-r10 all used, stride in r9), stride / 4 to +12776. Census: 34 a frame (Unreal's `82A531C8`, `82A53620`). |
| D3DDevice_ClearF | 826629E0 | **82B5D7E8** | (device, flags, count, rects, ...): with count 0 the rect is 0,0 to the size in render target 0 (+12688) or, without one, the depth surface (+12704), from the surface's +36 field. 21 game call sites. Runtime: 10.9 a frame, the same rate as its workers `82B5D170` → `82B5CBD8` (takes the Z value in f1) → `82B5C980`. |
| XGRegisterPixelShader | 82667AE0 | **82B54CE0** | 14 instructions: clears 40 bytes, type 7, reference 1, BaseFlush 0xFFFF0000 at +0x14, physical part at +0x18, exactly Renut's replacement. Called by Unreal's `82A57A68`, beside `82A57888` (the vertex one). Both come from `82425B70`, which looks like Unreal's shader cache loader. Census: 296 registrations in the run, against 174 distinct pixel shaders drawn. |
| Vertex declaration (in-place init) | CreateVertexDeclaration 82668088 | **82B551A0** | (elements r3, object r4): walks the 12-byte elements until stream 255, clears 56 + 12·n bytes of the object, type 0x00100005, reference 1, BaseFlush 0xFFFF0000, element count at +24, highest stream at +28. **Not CreateVertexDeclaration's shape**: under LTCG the callers (Unreal's `82A4EC38`, `82A54018`, `82A5C540`) allocate and this only fills the object, so Renut's hook (which returns a new object) needs rewriting. Census: 88 in the run. |
| D3DResource_AddRef / D3DResource_Release | | **82B4BEC0 / 82B4BF38** | Atomic +1 / −1 of the reference count at +4 (lwarx/stwcx.), recursing into the parent (+24) for type 4 with bit 30 set. 48 and 91 callers. |
| D3DResource_Destroy | 8265C778 | **82B4B730** | What Release calls when the count reaches 0. It also calls BlockOnFence: the GPU has to be done with the resource before it's freed. |
| D3D::InitializePresentationParameters | 82683188 | **82B65F08** | (device r3, present parameters r4): reads the parameters' fields (+0, +4, +8, +16, +40, +64) and calls VdQueryVideoMode. The hardware path `82B66420` passes it the argument CreateDevice received, so under LTCG **CreateDevice takes only the D3DPRESENT_PARAMETERS pointer** (r3). |
| D3D::InitializeApiState | 826827B8 | **82B65C30** | (device): fills the device's state from a static table at 0x822E0318 and reads BehaviorFlags (+24264). Called once, by the hardware path right after CreateDevice. |
| Resolve (copy worker) | 8266FD30 | **82B5DF10** | The only function programming RB_COPY_CONTROL (0x2318). Under LTCG it's called straight from game code (`sub_82A53D20`, `82A54E80`, `82A55EC0`), with no 19-instruction wrapper. |
| D3DResource_IsSet | 8265BD98 | **82B4C048** | Switch on the resource type: index buffer +12684, render targets +12688..+12700 and depth +12704, 16 stream sources from +12708, 26 textures from +12792, vertex shader +12944, pixel shader +12940. Callers `829A4488`, `82A57380`. |
| XGRegisterVertexShader | 8266AC10 | **82B54ED8** | Clears 872 bytes, type 6, reference 1, physical part at +0x20, container at +0x368. Called by Unreal's `sub_82A57888`. |

Still open, for the runtime census: ClearF (candidates `82B51E88`, `82B521D8`), XGRegisterPixelShader, the
CreateVertexShader/CreatePixelShader path, IsFencePending, InsertCallback, CBlocker::Check, BeginVertices. Also how
many shaders the game registers through XG versus loading them straight from its packages (gears2-nx saw only 7
shader objects created in Gears of War 2).

## Runtime census (2026-11-02, census build over 0x82A40000-0x82B80000, 7-minute run into the first gameplay area)

Measured in the 350-410 s window of gameplay: 1800 Swaps in 60 s, a steady **30 fps** (the game's own cap).

| Function | Calls | Notes |
|---|---|---|
| Swap `82B59050`, SynchronizeToPresentationInterval `82B58B18` | 1 / frame | Confirms both |
| CreateDevice `82B5C288` | 1 in the run | |
| DrawIndexedVertices `82B56180` | 444 / frame | |
| DrawVertices `82B55D68` | 12 / frame | |
| `82B55828` / `82B55368` (the UP draws) | 34 / frame, 1 / frame | `82B55828` is the main inline draw (probably DrawIndexedVerticesUP or the UP path Unreal uses for its UI and lines) |
| Resolve worker `82B5DF10` | 21 / frame | |
| `82B5BE88` | 748,000 / frame | A GPU-wait poll: CBlocker::Check (BlockOnFence calls it). A spin-wait that costs CPU on the Switch. |
| `82B4D048` | 79,000 / frame | Another polling loop. To identify. |
| XGRegisterVertexShader `82B54ED8` | **270 in the whole run** | Through Unreal's `82A57888` |

**Shaders.** The emulated GPU built pipelines with **84 distinct vertex shaders** and 174 distinct pixel shaders in the
same run, while 270 vertex shaders were registered through XGRegisterVertexShader. So, unlike Gears of War 2, Alice
appears to create its vertex shaders through XG. Capturing them at registration (Monster High's Renut method) should
work for vertex shaders. Not proven yet: the next check is to compare the registered microcode's hashes with the drawn
ones. The pixel shader registration isn't found yet. Under LTCG it may be inlined into Unreal's shader cache code
(`82A57CD0`, 64 calls a frame, which calls `82A57888` on a miss).

## More identified (static, 2026-11-02)

| What | Monster High | Alice | Evidence |
|---|---|---|---|
| D3DDevice_IsFencePending | 826719E8 | **82B583C0** | One argument. The device comes from an import slot chosen by KeGetCurrentProcessType == 2. Reads +11036 and +11024. |
| VdGlobalDevice import slot | 0x82000794 | **0x8200095C** | IsFencePending: the title process (type 2) reads `lwz 2396(0x82000000)`; the system one reads 0x82000958 (VdGlobalXamDevice) |
| Global qword copied into every device | 0x82C68C38 | **0x832F75D8** | CreateDevice: `lis r11,-31953` / `ld r11,30168(r11)` / `std r11,11008(r31)` |
| CBlocker::Check | 8265D768 | **82B5BE88** (probable) | BlockOnFence's callees are KickOff, `82B5BDC0` and `82B5BE88`. 82B5BE88 is the one polled 748,000 times a frame. |

## Renut's device offsets for Alice

Renut (app/src/renut_engine, `kDeviceOffset*`) reads 36 device fields. The rule found so far: the fields up to +11069
are Monster High's, and the fields from +12100 up are Monster High's − 128. Confirmed fields below. The rest follow
the rule until checked.

| Field | Monster High | Alice | Status |
|---|---|---|---|
| GlobalQword, CreationThreadId, IsTitleProcess | 11008, 11016, 11020 | same | confirmed (CreateDevice) |
| FenceCompletion, FenceTag, Flags, SwapFlags | 11024, 11036, 11068, 11069 | same | confirmed |
| SwapFenceTag | 11056 | 11056 | confirmed (Swap stores there) |
| VertexDeclaration | 12240 | 12112 | inferred (−128) |
| StreamStrides (u8 [16], stride / 4) | 12904 | 12776 | confirmed (both UP draws store there) |
| StreamSources [16], Textures [26] | 12836, 12920 | 12708, 12792 | confirmed (D3DResource_IsSet `82B4C048` loops 16 / 26 slots from these) |
| IndexBuffer, RenderTargets, DepthStencil | 12812, 12816, 12832 | 12684, 12688, 12704 | confirmed |
| PixelShader, VertexShader | 13068, 13072 | 12940, 12944 | confirmed (D3DResource_IsSet) |
| Predication | 13084 | 12956 | inferred |
| InKickOff, VerticesRingEnd, CommandBuffer | 13600, 13844, 13920 | 13472, 13716, 13792 | confirmed |
| PresentFenceTag | 15344 | 15216 | confirmed (Swap reads and writes it) |
| CriticalSection0/1 | 15348, 15376 | 15220, 15248 | inferred |
| SwapCount, SideBuffer | 16968, 17136 | 16840, 17008 | confirmed (Swap; CreateDevice's 4800-byte alloc) |
| PerfFrequency, TitleMinusOne, BehaviorFlags | 21996, 23380, 24392 | 21868, 23252, 24264 | BehaviorFlags confirmed (CreateDevice stores the constant 0x0C000001: LTCG folded the argument); the others inferred |

Renut functions not found yet for Alice: BeginVertices, InsertCallback. Under LTCG, some may be inlined into their callers, which
would need a different hook point.

## What this means for Renut (2026-11-02)

Retargeting Renut to Alice is **not only a table of new addresses**. LTCG changed the shape of several functions that
Renut replaces outright:

| Renut hook | What Renut assumes (XDK) | Alice |
|---|---|---|
| Direct3D_CreateDevice | (Adapter, DeviceType, -, BehaviorFlags r6, PresentParameters r7, out r8). Renut replaces it whole and then calls InitializePresentationParameters (device, pp) and InitializeApiState (device) itself. | `82B5C288` keeps only r3 (passed on to the hardware path `82B66420` as its second argument), and BehaviorFlags is the constant 0x0C000001. So CreateDevice is (present parameters). The two Init functions are `82B65F08` (presentation parameters) and `82B65C30` (API state), both called by `82B66420`. |
| D3DDevice_Resolve | an 11-argument wrapper | inlined; game code calls the copy worker `82B5DF10` directly |
| D3DDevice_DrawVerticesUP | (device, type, count, data, stride) | `82B55368` with the stride in r6 |
| CreateVertexDeclaration | (elements) returns a new object | `82B551A0` (elements, object) fills an object its callers allocated |

These four hooks need Alice-specific versions. The work is to follow Renut's intent (what each hook must record or
replace), read each function's real arguments from its callers, and test on PC against the emulated GPU frame by
frame (`compare_video.py`), as the porting prompt's stage 4 asks. The other hooks map one to one
(`tools/renut/retarget_alice.py`).

## Renut's hooks for Alice (2026-11-02, second pass)

Every value below was read from Alice's code with `tools/ppcdis.py`, `tools/find_disp.py` (a field's readers and
writers) and `tools/find_calls.py` (a function's callers). This pass **corrects** three entries above.

| Hook | Alice | Evidence |
|---|---|---|
| CreateDevice | hook of the hardware path **`82B66420`** (device, pp) | `82B5C288` has no type-2 path: it allocates and clears the device and calls `82B66420`, which does critical sections (+15220, +15248), VdGlobalDevice (slot 0x8200095C), fence words (+11024 96 bytes, +11028 32 bytes), the engines, `82B619A0` (XenonGpu_Initialize: writes +0x28BC 0x20002000, +0x29D4, +0x2A14), −1 at +21840/+21844, InitializePresentationParameters `82B65F08`, InitializeApiState `82B65C30`, the timer frequency at +21868, and 41 × −1 at +23664. The hook keeps the non-GPU part. |
| BeginVertices | **`82B55368`** (device, type, count, stride) → the vertex pointer | **Corrects the census:** not DrawVerticesUP. It reserves inline data (`82B57088`), returns it (`mr r3,r28`; 0 on failure) and stores +13716 (VerticesRingEnd), +13720, +13728. |
| BeginIndexedVertices | **`82B55828`** (device, type, base, NumVertices, IndexCount, format r8, stride r9, ppIndexData r10, ppVertexData at caller +84) → HRESULT | Bit 4 of r8 picks 32-bit indices; `stw r26,0(r17)` with r17 = r10; `stw r28,0(r9)` with r9 = `lwz 308(r1)` (frame 224: the caller's +84). New hook; deferred draws now carry indices. |
| DrawVerticesUP | **none** | Only BeginVertices, BeginIndexedVertices and SetStreamSource (`82B51DD0`, and the game's inline copy `82A5CE78`) store stream 0's stride byte (+12776). Hook dropped. |
| DrawIndexedVertices | `82B56180` (device, type, **StartIndex r5, IndexCount r6**) | **LTCG dropped BaseVertexIndex:** r5 is scaled by the index size, r6 is compared with 65535, and VGT_INDX_OFFSET (0x2102) is written from `li r17,0`. DrawVertices `82B55D68` keeps (device, type, StartVertex, VertexCount): it writes 0x2102 from r5. |
| Resolve | hook of the worker **`82B5DF10`** (device, flags, rect, dest texture, point, DestLevel r8, color r9, ClearZ f1, ClearStencil at caller +84) | 10 callers (9 game, Direct3D's Present `82B6761C`). r8: non-zero takes a mip level's offset; every caller passes 0. r9: `lvx` from it, a default when null. 0x200 flag calls `82B5D9B0` with `lwz r5,468(r1)` (frame 384). No slice, no parameters. |
| ClearF | `82B5D7E8` (device, flags, rect, color, f1 Z) | **No Stencil:** r8 and r7 are overwritten before any read; the worker `82B5D170` takes (device, flags, rect, color, f1). |
| Vertex declaration | hook of the in-place init **`82B551A0`** (elements, object) | 3 callers, all UE3 (`82A4ED00`, `82A540F0`, `82A5C5EC`). |
| InsertCallback | **none found** | Hook dropped. If UE3 inserts callbacks inline, their packets go to the ring sink and never run: watch for waits that never end. |
| Shader objects | as SA2's | XGRegisterVertexShader `82B54ED8` stores the physical pointer at +32 and reads the container at +872 (0x368); XGRegisterPixelShader `82B54CE0` stores it at +24. |

Device fields corrected or added: VertexDeclaration **12120** (not 12112: InitializeApiState stores the default
declaration's address, device + 12440, there; 4 users, none of 12112), the viewport floats at **12896** (SetViewport
`82B4F770`; SA2's 13024, N&B's 0x3168), ScissorRect 12924 (`82B4F2E0`), TilingExtent 13428 (ClearF), the gamma ramp
15280 (Swap), the presentation interval 13872 (InitializeApiState saves and restores it), TitleMinusOne 23664. Below
11072 (the register image, the fetch constants at +1152 and +1776, the fence words, the flags) the layout is SA2's.
The snapshot (`kDeviceSnapshotSize`) ends at 12960; the private range the deltas skip ends at 12096.

## UE3's bound shader state and the resolve exponent bias (2026-11-02, the black picture)

| What | Address | Evidence |
|---|---|---|
| UE3 RHISetBoundShaderState | **`82A51520`** (r3 = the bound shader state) | 90 call sites (`tools/find_calls.py 0x82A51520`). Unless `[0x832E1884]` > 1 and `[0x8336BA78]` != 0, it stores **0** at device +12120 (`82A51568 stw r10,12120(r11)` with `li r10,0`) and sets the vertex shader `[[state+4]+0]+8` (`82A51578`-`82A51588`, then `bl 82B54FD0`); otherwise it stores `[state+0]` there (`82A515A0`) and sets `[state+8]+8`. Both paths OR 0x80000 into the dirty mask at +16. The pixel shader is `[state+12]+8` (`bl 82B54D18`). |
| Bound shader state layout | +0 declaration, +4 wrapper of the vertex shader **bound** to it, +8 wrapper of the plain vertex shader, +12 wrapper of the pixel shader (each wrapper's +8 is the Direct3D object) | from the loads above |
| D3DVertexShader_Bind | **not found** (inlined under LTCG) | The +4 shader is set with a null declaration, so it must have been bound to the +0 declaration already. Renut's hook of `82A51520` gives that shader the declaration as `bound_declaration`. |
| Other stores of +12120 | `82A543B0` (UE3, a real object from `[r23-7896]`), InitializeApiState `82B65DCC`, `82B5C5CC`, `82DD68F4`, `83057EAC` | `tools/find_disp.py 12120`: 14 hits |
| Resolve exponent bias | flags bits 26-31, signed (D3DRESOLVE_EXPONENTBIAS) | The HDR scene resolves (RGBA16F 40044440 → texture 404A24C0) pass **F4000000**: bias −3, the colour × 1/8. Seen in `--banjo_renut_diag_resolve_trace=true`. |
