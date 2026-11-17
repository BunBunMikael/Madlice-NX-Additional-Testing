// alice-nx (2026-11-03): the game's own graphics settings, overridden after UE3 loads them (alice_shadows).
//
// UE3 keeps its graphics switches in [SystemSettings] of Xe-AliceEngine.ini (Coalesced_<lang>.bin on the disc):
// DynamicShadows = True, LightEnvironmentShadows = True, among ~80 others. sub_8242F4B0 loads one section of them
// into an FSystemSettingsData (r3 = the data, r4 = the section name, r5 = the ini file). It builds a table of
// (name, field) pairs on its stack first: 8242F530 stores L"DynamicShadows" (820C5F54) at sp+384, and 8242F55C
// stores r18 = r31+808 at sp+388; L"LightEnvironmentShadows" (820C5F74) at sp+392 goes with r31+812 at sp+396
// (r31 = r3). Its five callers: 82430CBC, 82430E18, 82430ED0, 8243175C (section 820C3C2C, L"SystemSettings") and
// 82432964 (r3 = this+4, L"SystemSettingsEditor" and L"SystemSettings").
//
// With alice_shadows off, both fields are zeroed after every load (the other alice_* switches below work the same way), so whatever section or file the game loads
// (the split-screen sections too), the renderer sees shadows disabled. The disc files are not touched.
// WHY: the user asked for shadows off (2026-11-03), for frame rate; the shadow depth passes are GPU work in every
// scene with a dynamic light. NOT EXACT: the picture changes (no dynamic shadows), by design.
#include <cstdint>
#include <cstring>

#include <rex/cvar.h>
#include <rex/hook.h>
#include <rex/logging.h>
#include <rex/ppc.h>
#include <rex/system/kernel_state.h>

REXCVAR_DEFINE_BOOL(alice_shadows, false, "ALICE",
                    "The game's dynamic shadows (UE3 SystemSettings DynamicShadows and LightEnvironmentShadows): "
                    "false = off (default, faster), true = the game's own setting. Read at each settings load");
// alice-nx (2026-11-03, the user: "improve FPS while the camera is looking at water, or turn off reflections"). The
// other switches of the same table, each true = the game's own value (default), false = forced off. Offsets from the
// table sub_8242F4B0 builds (name at sp+N, field r31+offset at sp+N+4), read by tools in docs/alice-notes.md.
REXCVAR_DEFINE_BOOL(alice_distortion, true, "ALICE",
                    "UE3 Distortion, FilteredDistortion, DropParticleDistortion: the refraction / heat-haze pass "
                    "(water surfaces, glass, particles). false = off. Read at each settings load");
REXCVAR_DEFINE_BOOL(alice_depth_of_field, true, "ALICE", "UE3 DepthOfField. false = off. Read at each settings load");
REXCVAR_DEFINE_BOOL(alice_bloom, true, "ALICE",
                    "UE3 UseHighQualityBloom. false = the cheaper bloom (bloom itself stays). Read at each settings "
                    "load");
REXCVAR_DEFINE_BOOL(alice_lens_flares, true, "ALICE", "UE3 LensFlares. false = off. Read at each settings load");
REXCVAR_DEFINE_BOOL(alice_fog_volumes, true, "ALICE", "UE3 FogVolumes. false = off. Read at each settings load");
// alice-nx (2026-11-03): numeric settings of the same table. ScreenPercentage +0x310 (float; the ini's 100.0, with
// UpscaleScreenPercentage = True the game renders the scene at that share of 1280x720 and scales it up: masseffect-nx
// got its GPU-bound scenes from 10-14 to 15-17 fps at 960x544 by a smaller guest video mode). ParticleLODBias +0x68
// (int, the ini's 0: higher picks the particle systems' cheaper LODs, the user's "cascade" lag).
REXCVAR_DEFINE_DOUBLE(alice_screen_percentage, 0.0, "ALICE",
                      "UE3 ScreenPercentage: the scene's render size in % of 1280x720, scaled up by the game "
                      "(75 = 960x540). 0 = the game's own (100). Read at each settings load")
    .range(0.0, 100.0);
// alice-nx (2026-11-03, the user: "change render distance to lower"): this UE3 has no global draw distance (each
// primitive keeps its own), so the draw-count levers of the same table. Decals: StaticDecals +0x0C, DynamicDecals
// +0x10, UnbatchedDecals +0x14 (UBOOL); DecalCullDistanceScale +0x18 and FoliageDrawRadiusMultiplier +0x308 (float);
// SkeletalMeshLODBias +0x64 (int). The fifth console run's slow windows were the ones with the most draws (~1,650 a
// frame at 20 fps against ~750 at 30) with the GPU under its budget (21-28 ms).
REXCVAR_DEFINE_BOOL(alice_decals, true, "ALICE",
                    "UE3 StaticDecals, DynamicDecals, UnbatchedDecals (blood, cracks, dirt drawn over surfaces). "
                    "false = off. Read at each settings load");
REXCVAR_DEFINE_DOUBLE(alice_decal_distance, 0.0, "ALICE",
                      "UE3 DecalCullDistanceScale: how far decals are drawn, as a share of the game's (0.5 = half). "
                      "0 = the game's own (1.0). Read at each settings load")
    .range(0.0, 1.0);
REXCVAR_DEFINE_DOUBLE(alice_foliage_distance, 0.0, "ALICE",
                      "UE3 FoliageDrawRadiusMultiplier: how far foliage is drawn, as a share of the game's (0.5 = "
                      "half). 0 = the game's own (1.0). Read at each settings load")
    .range(0.0, 1.0);
REXCVAR_DEFINE_INT32(alice_skeletal_lod_bias, -1, "ALICE",
                     "UE3 SkeletalMeshLODBias: 1, 2, ... = cheaper character and creature models; -1 = the game's "
                     "own (0). Read at each settings load")
    .range(-1, 4);
REXCVAR_DEFINE_INT32(alice_particle_lod_bias, -1, "ALICE",
                     "UE3 ParticleLODBias: 1, 2, ... = cheaper particle LODs; -1 = the game's own (0). Read at each "
                     "settings load")
    .range(-1, 8);
// alice-nx (2026-11-04, the user on a Switch Lite: "any other improvement"): the rest of the table's cost switches.
// MotionBlur +0x2C and AllowRadialBlur +0x70 are full-screen post passes; DynamicLights +0x1C draws every object a
// dynamic light touches once more per light (the draw count is what the forest views are bound by), and
// CompositeDynamicLights +0x20 = True folds the unshadowed ones into the light environments instead (UE3's cheap path).
// OneFrameThreadLag +0x60 lets the render thread run a frame behind the game thread (logged, never changed).
REXCVAR_DEFINE_BOOL(alice_motion_blur, true, "ALICE", "UE3 MotionBlur. false = off. Read at each settings load");
REXCVAR_DEFINE_BOOL(alice_radial_blur, true, "ALICE",
                    "UE3 AllowRadialBlur (the radial blur effects). false = off. Read at each settings load");
REXCVAR_DEFINE_BOOL(alice_dynamic_lights, true, "ALICE",
                    "UE3 DynamicLights. false = off (fewer draws, flatter lighting). Read at each settings load");
REXCVAR_DEFINE_BOOL(alice_composite_lights, false, "ALICE",
                    "UE3 CompositeDynamicLights forced on (dynamic lights merged into the light environments, fewer "
                    "draws). false = the game's own. Read at each settings load");

namespace {

struct Override {
  bool (*keep)();
  const char *name;
  uint32_t offset;  // FSystemSettingsData field, UBOOL
};

const Override kOverrides[] = {
    {[] { return REXCVAR_GET(alice_motion_blur); }, "MotionBlur", 0x2C},
    {[] { return REXCVAR_GET(alice_motion_blur); }, "MotionBlurPause", 0x34},
    {[] { return REXCVAR_GET(alice_radial_blur); }, "AllowRadialBlur", 0x70},
    {[] { return REXCVAR_GET(alice_dynamic_lights); }, "DynamicLights", 0x1C},
    {[] { return REXCVAR_GET(alice_shadows); }, "DynamicShadows", 0x328},
    {[] { return REXCVAR_GET(alice_shadows); }, "LightEnvironmentShadows", 0x32C},
    {[] { return REXCVAR_GET(alice_distortion); }, "Distortion", 0x48},
    {[] { return REXCVAR_GET(alice_distortion); }, "FilteredDistortion", 0x4C},
    {[] { return REXCVAR_GET(alice_distortion); }, "DropParticleDistortion", 0x50},
    {[] { return REXCVAR_GET(alice_depth_of_field); }, "DepthOfField", 0x38},
    {[] { return REXCVAR_GET(alice_bloom); }, "UseHighQualityBloom", 0x44},
    {[] { return REXCVAR_GET(alice_lens_flares); }, "LensFlares", 0x54},
    {[] { return REXCVAR_GET(alice_fog_volumes); }, "FogVolumes", 0x58},
    {[] { return REXCVAR_GET(alice_decals); }, "StaticDecals", 0x0C},
    {[] { return REXCVAR_GET(alice_decals); }, "DynamicDecals", 0x10},
    {[] { return REXCVAR_GET(alice_decals); }, "UnbatchedDecals", 0x14},
};

// A float setting: set to 'value' when 'value' > 0.
struct FloatOverride {
  double (*value)();
  const char *name;
  uint32_t offset;
};
const FloatOverride kFloatOverrides[] = {
    {[] { return REXCVAR_GET(alice_screen_percentage); }, "ScreenPercentage", 0x310},
    {[] { return REXCVAR_GET(alice_decal_distance); }, "DecalCullDistanceScale", 0x18},
    {[] { return REXCVAR_GET(alice_foliage_distance); }, "FoliageDrawRadiusMultiplier", 0x308},
};

// An integer setting: set to 'value' when 'value' >= 0.
struct IntOverride {
  int32_t (*value)();
  const char *name;
  uint32_t offset;
};
const IntOverride kIntOverrides[] = {
    {[] { return REXCVAR_GET(alice_particle_lod_bias); }, "ParticleLODBias", 0x68},
    {[] { return REXCVAR_GET(alice_skeletal_lod_bias); }, "SkeletalMeshLODBias", 0x64},
};

uint32_t LoadBE(uint32_t va) {
  const uint8_t *p = REX_KERNEL_MEMORY()->TranslateVirtual<const uint8_t *>(va);
  return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3];
}

void StoreBE(uint32_t va, uint32_t v) {
  uint8_t *p = REX_KERNEL_MEMORY()->TranslateVirtual<uint8_t *>(va);
  p[0] = uint8_t(v >> 24);
  p[1] = uint8_t(v >> 16);
  p[2] = uint8_t(v >> 8);
  p[3] = uint8_t(v);
}

}  // namespace

REX_EXTERN(__imp__sub_8242F4B0);

extern "C" REX_FUNC(sub_8242F4B0) {
  const uint32_t data = ctx.r3.u32;
  __imp__sub_8242F4B0(ctx, base);
  if (!data)
    return;
  static int logged = 0;
  if (logged < 64) {
    logged += 2;
    REXLOG_INFO("[alice] settings {:08X}: MotionBlur {} AllowRadialBlur {} DynamicLights {} CompositeDynamicLights {} "
                "OneFrameThreadLag {} SHSecondaryLighting {}",
                data, LoadBE(data + 0x2C), LoadBE(data + 0x70), LoadBE(data + 0x1C), LoadBE(data + 0x20),
                LoadBE(data + 0x60), LoadBE(data + 0x24));
  }
  if (REXCVAR_GET(alice_composite_lights))
    StoreBE(data + 0x20, 1);
  for (const FloatOverride &o : kFloatOverrides) {
    const double v = o.value();
    if (v <= 0.0)
      continue;
    const float f = float(v);
    uint32_t bits, was;
    std::memcpy(&bits, &f, 4);
    was = LoadBE(data + o.offset);
    StoreBE(data + o.offset, bits);
    if (logged < 64) {
      ++logged;
      float old;
      std::memcpy(&old, &was, 4);
      REXLOG_INFO("[alice] settings {:08X}: {} {} -> {}", data, o.name, old, f);
    }
  }
  for (const IntOverride &o : kIntOverrides) {
    const int32_t v = o.value();
    if (v < 0)
      continue;
    const uint32_t was = LoadBE(data + o.offset);
    StoreBE(data + o.offset, uint32_t(v));
    if (logged < 64) {
      ++logged;
      REXLOG_INFO("[alice] settings {:08X}: {} {} -> {}", data, o.name, int32_t(was), v);
    }
  }
  for (const Override &o : kOverrides) {
    if (o.keep())
      continue;
    const uint32_t was = LoadBE(data + o.offset);
    StoreBE(data + o.offset, 0);
    if (logged < 64) {
      ++logged;
      REXLOG_INFO("[alice] settings {:08X}: {} {} -> 0", data, o.name, was);
    }
  }
}
