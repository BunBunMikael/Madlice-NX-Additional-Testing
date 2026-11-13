#include "utility.hlsli"

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

// alice-nx (2026-11-13): FSR 1 (AMD FidelityFX Super Resolution 1.0: EASU edge-adaptive upscaling, then an RCAS-style
// sharpen), written as one pass over the frame texture. samplerIndex's bits: 0-7 the sampler slot, 8 = FSR on, 16-23 the
// sharpening (0-255 = 0-1). The taps are texel loads clamped to the texture, so the frame's own edge is not crossed
// (a texture larger than the frame shows its unused margin to the filter at the frame's right and bottom edge only).
// EASU's constants and tap weights are AMD's (ffx_fsr1.h, MIT).
float3 FsrLoad(uint tex, int2 p, int2 dim)
{
    p = clamp(p, int2(0, 0), dim - 1);
    return g_Textures[NonUniformResourceIndex(tex)].Load(int3(p, 0)).rgb;
}

float FsrLuma(float3 c)
{
    return c.b * 0.5 + (c.r * 0.5 + c.g);
}

void FsrEasuSet(inout float2 dir, inout float len, float w, float lA, float lB, float lC, float lD, float lE)
{
    float lenX = max(abs(lD - lC), abs(lC - lB));
    float dirX = lD - lB;
    dir.x += dirX * w;
    lenX = saturate(abs(dirX) / max(lenX, 1e-8));
    lenX *= lenX;
    len += lenX * w;
    float lenY = max(abs(lE - lC), abs(lC - lA));
    float dirY = lE - lA;
    dir.y += dirY * w;
    lenY = saturate(abs(dirY) / max(lenY, 1e-8));
    lenY *= lenY;
    len += lenY * w;
}

void FsrEasuTap(inout float3 aC, inout float aW, float2 off, float2 dir, float2 len, float lob, float clp, float3 c)
{
    float2 v;
    v.x = off.x * dir.x + off.y * dir.y;
    v.y = off.x * (-dir.y) + off.y * dir.x;
    v *= len;
    float d2 = min(v.x * v.x + v.y * v.y, clp);
    float wB = 2.0 / 5.0 * d2 - 1.0;
    float wA = lob * d2 - 1.0;
    wB *= wB;
    wA *= wA;
    wB = 25.0 / 16.0 * wB - (25.0 / 16.0 - 1.0);
    float w = wB * wA;
    aC += c * w;
    aW += w;
}

float3 FsrEasu(uint tex, float2 uv)
{
    uint tw, th;
    g_Textures[NonUniformResourceIndex(tex)].GetDimensions(tw, th);
    const int2 dim = int2(int(tw), int(th));
    // The pixel's centre in source texels, less half a texel: the top-left texel of its 2x2 is floor of it.
    float2 pp = uv * float2(dim) - 0.5;
    const float2 fp = floor(pp);
    pp -= fp;
    const int2 f0 = int2(fp);
    //    b c
    //  e f g h
    //  i j k l
    //    n o
    const float3 bC = FsrLoad(tex, f0 + int2(0, -1), dim);
    const float3 cC = FsrLoad(tex, f0 + int2(1, -1), dim);
    const float3 eC = FsrLoad(tex, f0 + int2(-1, 0), dim);
    const float3 fC = FsrLoad(tex, f0 + int2(0, 0), dim);
    const float3 gC = FsrLoad(tex, f0 + int2(1, 0), dim);
    const float3 hC = FsrLoad(tex, f0 + int2(2, 0), dim);
    const float3 iC = FsrLoad(tex, f0 + int2(-1, 1), dim);
    const float3 jC = FsrLoad(tex, f0 + int2(0, 1), dim);
    const float3 kC = FsrLoad(tex, f0 + int2(1, 1), dim);
    const float3 lC = FsrLoad(tex, f0 + int2(2, 1), dim);
    const float3 nC = FsrLoad(tex, f0 + int2(0, 2), dim);
    const float3 oC = FsrLoad(tex, f0 + int2(1, 2), dim);
    const float bL = FsrLuma(bC), cL = FsrLuma(cC), eL = FsrLuma(eC), fL = FsrLuma(fC), gL = FsrLuma(gC);
    const float hL = FsrLuma(hC), iL = FsrLuma(iC), jL = FsrLuma(jC), kL = FsrLuma(kC), lL = FsrLuma(lC);
    const float nL = FsrLuma(nC), oL = FsrLuma(oC);

    float2 dir = float2(0.0, 0.0);
    float len = 0.0;
    FsrEasuSet(dir, len, (1.0 - pp.x) * (1.0 - pp.y), bL, eL, fL, gL, jL);
    FsrEasuSet(dir, len, pp.x * (1.0 - pp.y), cL, fL, gL, hL, kL);
    FsrEasuSet(dir, len, (1.0 - pp.x) * pp.y, fL, iL, jL, kL, nL);
    FsrEasuSet(dir, len, pp.x * pp.y, gL, jL, kL, lL, oL);

    const float2 dir2 = dir * dir;
    float dirR = dir2.x + dir2.y;
    const bool zro = dirR < (1.0 / 32768.0);
    dirR = rsqrt(max(dirR, 1e-12));
    dirR = zro ? 1.0 : dirR;
    dir.x = zro ? 1.0 : dir.x;
    dir *= dirR;
    len = len * 0.5;
    len *= len;
    const float stretch = (dir.x * dir.x + dir.y * dir.y) / max(max(abs(dir.x), abs(dir.y)), 1e-8);
    const float2 len2 = float2(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len);
    const float lob = 0.5 + ((1.0 / 4.0 - 0.04) - 0.5) * len;
    const float clp = 1.0 / lob;

    const float3 min4 = min(min(fC, gC), min(jC, kC));
    const float3 max4 = max(max(fC, gC), max(jC, kC));
    float3 aC = float3(0.0, 0.0, 0.0);
    float aW = 0.0;
    FsrEasuTap(aC, aW, float2(0.0, -1.0) - pp, dir, len2, lob, clp, bC);
    FsrEasuTap(aC, aW, float2(1.0, -1.0) - pp, dir, len2, lob, clp, cC);
    FsrEasuTap(aC, aW, float2(-1.0, 1.0) - pp, dir, len2, lob, clp, iC);
    FsrEasuTap(aC, aW, float2(0.0, 1.0) - pp, dir, len2, lob, clp, jC);
    FsrEasuTap(aC, aW, float2(0.0, 0.0) - pp, dir, len2, lob, clp, fC);
    FsrEasuTap(aC, aW, float2(-1.0, 0.0) - pp, dir, len2, lob, clp, eC);
    FsrEasuTap(aC, aW, float2(1.0, 1.0) - pp, dir, len2, lob, clp, kC);
    FsrEasuTap(aC, aW, float2(2.0, 1.0) - pp, dir, len2, lob, clp, lC);
    FsrEasuTap(aC, aW, float2(2.0, 0.0) - pp, dir, len2, lob, clp, hC);
    FsrEasuTap(aC, aW, float2(1.0, 0.0) - pp, dir, len2, lob, clp, gC);
    FsrEasuTap(aC, aW, float2(1.0, 2.0) - pp, dir, len2, lob, clp, oC);
    FsrEasuTap(aC, aW, float2(0.0, 2.0) - pp, dir, len2, lob, clp, nC);
    return min(max4, max(min4, aC / max(aW, 1e-8)));
}

float4 main(PSInput input) : SV_Target0
{
    const uint samplerSlot = g_Push.samplerIndex & 0xFFu;
    const bool fsr = (g_Push.samplerIndex & 0x100u) != 0u;
    float4 color;
    if (fsr)
    {
        // Sharpening (RCAS's formula, FSR 1's second pass): the neighbours one output pixel away are bilinear taps of
        // the source rather than EASU's own output, which would need a second pass over an intermediate target.
        const float2 px = float2(abs(ddx(input.uv.x)), abs(ddy(input.uv.y)));
        const float sharp = float((g_Push.samplerIndex >> 16) & 0xFFu) * (1.0 / 255.0);
        const float3 e = FsrEasu(g_Push.textureIndex, input.uv);
        float3 b = SampleBindless(g_Push.textureIndex, 0u, input.uv + float2(0.0, -px.y)).rgb;
        float3 d = SampleBindless(g_Push.textureIndex, 0u, input.uv + float2(-px.x, 0.0)).rgb;
        float3 f = SampleBindless(g_Push.textureIndex, 0u, input.uv + float2(px.x, 0.0)).rgb;
        float3 h = SampleBindless(g_Push.textureIndex, 0u, input.uv + float2(0.0, px.y)).rgb;
        const float3 mn4 = min(min(b, d), min(f, h));
        const float3 mx4 = max(max(b, d), max(f, h));
        const float3 hitMin = mn4 / (4.0 * mx4 + 1e-5);
        const float3 hitMax = (1.0 - mx4) / (4.0 * mn4 - 4.0 - 1e-5);
        const float3 lobeRgb = max(-hitMin, hitMax);
        const float lobe = max(-0.1875, min(max(lobeRgb.r, max(lobeRgb.g, lobeRgb.b)), 0.0)) * sharp;
        color = float4(saturate((lobe * (b + d + f + h) + e) / (4.0 * lobe + 1.0)), 1.0);
    }
    else
    {
        color = SampleBindless(g_Push.textureIndex, samplerSlot, input.uv);
    }
    // sa2-nx (2026-10-20): param1's bits, when not 0, = the bindless slot of the game's display gamma ramp
    // (SetGammaRamp; the Xbox 360's display controller applies it at scan-out): 256 texels of red, green, blue in 0-1.
    // The same lookup as the emulated GPU's and sa2-nx's native renderer's output pass: each channel's 8-bit value picks
    // its entry. The slot is read as it is, with no arithmetic: an emulator (Ryujinx) follows a bindless handle only
    // back to a constant buffer load, and a computed one read zero (a black picture).
    const uint ramp = asuint(g_Push.param1);
    if (ramp != 0u)
    {
        const uint3 i = uint3(saturate(color.rgb) * 255.0 + 0.5);
        color.rgb = float3(g_Textures[NonUniformResourceIndex(ramp)].Load(int3(i.x, 0, 0)).x,
                           g_Textures[NonUniformResourceIndex(ramp)].Load(int3(i.y, 0, 0)).y,
                           g_Textures[NonUniformResourceIndex(ramp)].Load(int3(i.z, 0, 0)).z);
    }
    // param0 = output gamma exponent (1 = passthrough). sa2-nx: skipped at 1, where pow's exp2(log2) could move a
    // value by an ulp.
    if (g_Push.param0 != 1.0)
        color.rgb = pow(saturate(color.rgb), g_Push.param0);
    return float4(color.rgb, 1.0);
}
