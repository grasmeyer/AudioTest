//
//  RaymarchShader.metal
//  AudioTest
//
//  A minimal raymarched 3D scene: one signed-distance-function sphere floating
//  in a procedural sky. The point is the end-to-end raymarch loop (ray setup →
//  sphere-trace → normal → shade → sky) so the SDF can later be swapped for a
//  fractal or other geometry. Bass hits shake the camera; RMS drives a cheap
//  single-pass glow ("bloom"); the spectral centroid tints the palette.
//

#include <metal_stdlib>
using namespace metal;

struct RaymarchUniforms {
    float time;
    float shake;        // camera-shake amount (bass-hit driven)
    float bloom;        // glow intensity (audio-driven)
    float camDistance;  // camera distance from the sphere
    float fov;          // field-of-view scale
    float sphereRadius;
    float hue;          // palette tint (centroid-driven + manual)
    float brightness;
    float2 resolution;
};

struct RMVSOut {
    float4 position [[position]];
    float2 uv;
};

vertex RMVSOut raymarchVertex(uint vid [[vertex_id]]) {
    float2 verts[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    RMVSOut o;
    float2 p = verts[vid];
    o.position = float4(p, 0.0, 1.0);
    o.uv = p * 0.5 + 0.5;
    return o;
}

// iq cosine palette for tinting.
static inline float3 palette(float t) {
    return 0.5 + 0.5 * cos(6.28318 * (t + float3(0.0, 0.33, 0.67)));
}

// Signed distance to the scene: a single sphere at the origin.
static inline float mapScene(float3 p, constant RaymarchUniforms &u) {
    return length(p) - u.sphereRadius;
}

static inline float3 calcNormal(float3 p, constant RaymarchUniforms &u) {
    float2 e = float2(0.0015, 0.0);
    float d = mapScene(p, u);
    float3 n = d - float3(mapScene(p - e.xyy, u),
                          mapScene(p - e.yxy, u),
                          mapScene(p - e.yyx, u));
    return normalize(n);
}

static inline float3 skyColor(float3 rd, constant RaymarchUniforms &u) {
    float t = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);
    float3 col = mix(float3(0.14, 0.17, 0.27), float3(0.02, 0.03, 0.08), t);

    // A soft sun glow tinted by the palette.
    float3 sunDir = normalize(float3(0.6, 0.45, -0.5));
    float sun = pow(max(dot(rd, sunDir), 0.0), 64.0);
    col += palette(u.hue) * sun * 1.5;

    // Subtle star sparkle high in the sky.
    float stars = pow(max(rd.y, 0.0), 3.0) *
                  step(0.9992, fract(sin(dot(floor(rd.xz * 600.0), float2(12.99, 78.23))) * 43758.5));
    col += stars;
    return col;
}

fragment float4 raymarchFragment(RMVSOut in [[stage_in]],
                                 constant RaymarchUniforms &u [[buffer(0)]]) {
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= aspect;

    // Camera, jittered by bass hits.
    float2 jitter = float2(sin(u.time * 37.0), cos(u.time * 41.0)) * u.shake * 0.12;
    float3 ro = float3(jitter, -u.camDistance);
    float3 target = float3(jitter * 0.5, 0.0);

    float3 fwd = normalize(target - ro);
    float3 right = normalize(cross(float3(0.0, 1.0, 0.0), fwd));
    float3 up = cross(fwd, right);
    float3 rd = normalize(uv.x * right + uv.y * up + fwd * u.fov);

    // Sphere-trace the scene.
    float t = 0.0;
    float minDist = 1e9;
    bool hit = false;
    float3 p = ro;
    for (int i = 0; i < 96; i++) {
        p = ro + rd * t;
        float d = mapScene(p, u);
        minDist = min(minDist, d);
        if (d < 0.001) { hit = true; break; }
        t += d;
        if (t > 24.0) break;
    }

    float3 col;
    if (hit) {
        float3 n = calcNormal(p, u);
        float3 lightDir = normalize(float3(0.6, 0.7, -0.4));
        float diff = max(dot(n, lightDir), 0.0);
        float3 base = palette(u.hue);
        col = base * (0.2 + 0.8 * diff);

        float3 h = normalize(lightDir - rd);
        col += pow(max(dot(n, h), 0.0), 32.0) * 0.6;

        // Fresnel rim feeds the glow.
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        col += base * fres * 0.6;
    } else {
        col = skyColor(rd, u);
    }

    // Cheap single-pass bloom: glow halo near the silhouette, audio-scaled.
    float glow = exp(-minDist * 6.0);
    col += palette(u.hue + 0.1) * glow * u.bloom;

    col *= u.brightness;
    col = pow(max(col, 0.0), float3(0.4545)); // gamma
    return float4(col, 1.0);
}
