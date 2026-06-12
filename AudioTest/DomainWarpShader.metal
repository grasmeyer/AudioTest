//
//  DomainWarpShader.metal
//  AudioTest
//
//  A ShaderToy-style full-screen 2D scene using Inigo Quilez's domain-warping
//  technique: fbm noise sampled at coordinates that are themselves displaced by
//  more fbm noise, producing organic, flowing textures. Audio drives the warp
//  amount (bass), the color palette (spectral centroid), and the scroll speed
//  (RMS), via a CPU-accumulated scroll phase.
//

#include <metal_stdlib>
using namespace metal;

struct ShaderUniforms {
    float time;        // animates the internal warp layers
    float warp;        // domain-warp amount (bass-driven)
    float palette;     // palette phase shift (spectral-centroid-driven)
    float scroll;      // accumulated scroll phase (RMS-driven)
    float zoom;        // spatial scale of the field
    float contrast;    // contrast curve strength
    float brightness;  // overall brightness
    float2 resolution; // drawable size in pixels
};

// --- Value noise / fbm -------------------------------------------------------

static inline float dwHash(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

static inline float dwNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = dwHash(i + float2(0.0, 0.0));
    float b = dwHash(i + float2(1.0, 0.0));
    float c = dwHash(i + float2(0.0, 1.0));
    float d = dwHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float dwFbm(float2 p) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        sum += amp * dwNoise(p);
        p *= 2.02;
        amp *= 0.5;
    }
    return sum;
}

// iq cosine palette: a + b * cos(2pi * (c*t + d)).
static inline float3 palette(float t, float3 d) {
    const float3 a = float3(0.5);
    const float3 b = float3(0.5);
    const float3 c = float3(1.0);
    return a + b * cos(6.28318 * (c * t + d));
}

// --- Full-screen pass --------------------------------------------------------

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut fullscreenVertex(uint vid [[vertex_id]]) {
    // Oversized triangle covering the whole screen.
    float2 verts[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VSOut o;
    float2 p = verts[vid];
    o.position = float4(p, 0.0, 1.0);
    o.uv = p * 0.5 + 0.5;
    return o;
}

fragment float4 domainWarpFragment(VSOut in [[stage_in]],
                                   constant ShaderUniforms &u [[buffer(0)]]) {
    // Aspect-correct, centered coordinates with a gentle zoom.
    float2 p = in.uv * 2.0 - 1.0;
    p.x *= u.resolution.x / max(u.resolution.y, 1.0);
    p *= u.zoom;

    // Slow drift so the field scrolls; RMS makes it flow faster.
    float2 drift = float2(u.scroll * 0.12, u.scroll * 0.05);
    float t = u.time;

    // Domain warping: q displaces p, r displaces that, then sample the field.
    float2 q = float2(
        dwFbm(p + drift),
        dwFbm(p + drift + float2(5.2, 1.3))
    );
    float2 r = float2(
        dwFbm(p + u.warp * q + float2(1.7, 9.2) + 0.15 * t),
        dwFbm(p + u.warp * q + float2(8.3, 2.8) + 0.126 * t)
    );
    float f = dwFbm(p + u.warp * r);

    // Color: palette phase shifted by the spectral centroid, enriched by the
    // intermediate warp fields for depth.
    float3 col = palette(f + 0.1 * u.scroll + u.palette,
                         float3(0.0, 0.33, 0.67));
    col = mix(col, palette(f + u.palette + 0.4, float3(0.3, 0.2, 0.2)),
              clamp(dot(q, q), 0.0, 1.0));
    col = mix(col, palette(f + u.palette + 0.7, float3(0.1, 0.5, 0.8)),
              clamp(r.x * r.x, 0.0, 1.0));

    // Contrast curve so highlights bloom and shadows deepen.
    col *= (f * f * f + 0.6 * f * f + 0.5 * f) * u.contrast + 0.15;
    col *= u.brightness;

    return float4(col, 1.0);
}
