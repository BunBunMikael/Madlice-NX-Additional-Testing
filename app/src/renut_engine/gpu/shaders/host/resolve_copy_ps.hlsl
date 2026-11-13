// banjo-nx (2026-10-18): a colour resolve drawn instead of copied (draw.cpp, DrawResolveCopy). deko3d copies images on
// the copy engine, which needs the whole GPU idle before and after it; a draw is ordered like any other. The destination
// pixel plus g_Push.translate is the source texel, read with Load through a view of the surface's own format (the
// destination has the same format, so every texel is written back with its bits). present_vs draws the fullscreen
// triangle; the scissor limits it to the resolved rect.
#include "utility.hlsli"

float4 main(float4 position : SV_Position) : SV_Target0
{
    const int2 texel = int2(position.xy) + int2(g_Push.translate);
    const float4 value = g_Textures[NonUniformResourceIndex(g_Push.textureIndex)].Load(int3(texel, 0));
    // alice-nx (2026-11-02): param0, when not 0, is the resolve's exponent bias as a factor (2^bias, D3DRESOLVE flag
    // bits 26-31): Alice's HDR scene resolves pass -3. 0 (every other caller) copies the bits as before.
    return g_Push.param0 != 0.0f ? value * g_Push.param0 : value;
}
