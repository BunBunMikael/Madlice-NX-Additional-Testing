// The addresses both renderers hook (banjo-nx's tools/renut_gpu_import.py generated this list for N&B). sa2-nx
// (2026-10-20): SA2's. sa2-nx's own hook there (src/me, src/cpu) calls renut_native_sub_X when Renut's renderer is
// chosen (sa2_renut_yield.h).
#pragma once

#include <rex/ppc.h>

extern "C" void renut_native_sub_82B57088(PPCContext& ctx, uint8_t* base);  // AllocateInlineData
extern "C" void renut_native_sub_82B5BE88(PPCContext& ctx, uint8_t* base);  // CBlocker::Check
extern "C" void renut_native_sub_82B55368(PPCContext& ctx, uint8_t* base);  // D3DDevice_BeginVertices
extern "C" void renut_native_sub_82674178(PPCContext& ctx, uint8_t* base);  // D3DDevice_DrawVerticesUP
extern "C" void renut_native_sub_82B55D68(PPCContext& ctx, uint8_t* base);  // D3DDevice_DrawVertices
extern "C" void renut_native_sub_82B56180(PPCContext& ctx, uint8_t* base);  // D3DDevice_DrawIndexedVertices
