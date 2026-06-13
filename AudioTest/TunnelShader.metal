//
//  TunnelShader.metal
//  AudioTest
//
//  An infinite tunnel of repeating, rotating SDF boxes with a cosine palette,
//  ported from James Porter's raymarching gist
//  (gist.github.com/jamesporter/1b33558b3fc2771b45630ba7e0ba5122).
//  Audio drives the flythrough speed (RMS), box rotation (bass), box size
//  (beat pulse), and palette hue (spectral centroid).
//

#include <metal_stdlib>
using namespace metal;

struct TunnelUniforms {
    float time;       // sway / palette animation
    float travel;     // accumulated forward travel (RMS-driven)
    float rotPhase;   // accumulated rotation phase (bass-driven)
    float boxSize;    // box half-size (beat-pulsed)
    float hue;        // palette phase shift (centroid-driven + manual)
    float sway;       // camera x-sway amount
    float brightness;
    float2 resolution;
};

struct TunnelVSOut {
    float4 position [[position]];
    float2 uv;
};

vertex TunnelVSOut tunnelVertex(uint vid [[vertex_id]]) {
    float2 verts[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    TunnelVSOut o;
    float2 p = verts[vid];
    o.position = float4(p, 0.0, 1.0);
    o.uv = p * 0.5 + 0.5;
    return o;
}

static inline float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

static inline float2x2 rot2D(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2x2(c, -s, s, c);
}

static inline float3 palette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318 * (c * t + d));
}

static inline float modf2(float a, float b) {
    return a - b * floor(a / b);
}

// Domain-repeated, rotating boxes.
static inline float mapScene(float3 p, constant TunnelUniforms &u) {
    float3 q = float3(fract(p.xy) - 0.5, modf2(p.z, 0.5) - 0.25);
    q.xy = q.xy * rot2D(u.rotPhase + floor(p.z));
    return sdBox(q, float3(u.boxSize));
}

fragment float4 tunnelFragment(TunnelVSOut in [[stage_in]],
                               constant TunnelUniforms &u [[buffer(0)]]) {
    // Aspect-correct coordinates (matches the gist's (position*2 - size)/size.y).
    float2 frag = in.uv * u.resolution;
    float2 uv = (frag * 2.0 - u.resolution) / u.resolution.y;

    // Camera flies forward through the tunnel, swaying side to side.
    float3 ro = float3(sin(u.time) * u.sway, 0.0, -3.0 + u.travel);
    float3 rd = normalize(float3(uv, 1.0));

    float t = 0.0;
    int j = 0;
    for (int i = 0; i < 80; i++) {
        float3 p = ro + rd * t;
        float d = mapScene(p, u);
        t += d;
        j = i;
        if (d < 0.001 || t > 12.0) break;
    }

    float3 col = palette(t * 0.9 + u.time * 0.01 + float(j) * 0.01 + u.hue,
                         float3(0.5), float3(0.5), float3(1.0),
                         float3(0.0, 0.2, 0.2));

    col *= u.brightness;
    return float4(col, 1.0);
}
