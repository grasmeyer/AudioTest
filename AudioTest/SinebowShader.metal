//
//  SinebowShader.metal
//  AudioTest
//
//  A full-screen "sinebow" effect adapted from the Inferno project's Sinebow
//  shader (github.com/twostraws/Inferno): a stack of sine waves, each tinted
//  across the rainbow, with a 1/distance glow that produces bright neon bands.
//  Audio drives the wave strength (bass), animation speed (RMS), and color
//  cycle (spectral centroid).
//

#include <metal_stdlib>
using namespace metal;

struct SinebowUniforms {
    float time;        // accumulated animation phase (RMS-driven speed)
    float waveCount;   // number of stacked waves
    float strength;    // wave displacement amount (bass-driven)
    float thickness;   // band thinness (larger = thinner, brighter bands)
    float brightness;  // overall brightness
    float hueShift;    // color-cycle phase (centroid-driven + manual)
    float2 resolution; // drawable size in pixels
};

struct SinebowVSOut {
    float4 position [[position]];
    float2 uv;
};

vertex SinebowVSOut sinebowVertex(uint vid [[vertex_id]]) {
    float2 verts[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    SinebowVSOut o;
    float2 p = verts[vid];
    o.position = float4(p, 0.0, 1.0);
    o.uv = p * 0.5 + 0.5;
    return o;
}

fragment half4 sinebowFragment(SinebowVSOut in [[stage_in]],
                               constant SinebowUniforms &u [[buffer(0)]]) {
    // Aspect-correct coordinates in -1...1.
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= aspect;

    half3 waveColor = half3(0.0);
    int count = int(clamp(u.waveCount, 1.0, 30.0));

    for (int i = 0; i < count; i++) {
        float fi = float(i);

        // Each wave is a sine of x (with increasing frequency), displaced in y.
        float wave = sin(uv.x * (fi + 1.0) + u.time) * u.strength;

        // 1/distance glow: bright where the wave passes through this pixel's row.
        float luma = abs(1.0 / (u.thickness * uv.y + wave));

        // Rainbow tint per wave — the "sinebow".
        float r = sin(fi * 0.3 + u.time + u.hueShift) * 0.5 + 0.5;
        float g = sin(fi * 0.3 + 2.094 + u.time + u.hueShift) * 0.5 + 0.5;
        float b = sin(fi * 0.3 + 4.188 + u.time + u.hueShift) * 0.5 + 0.5;

        waveColor += half3(half(r), half(g), half(b)) * half(luma);
    }

    waveColor *= half(u.brightness);
    return half4(waveColor, 1.0);
}
