//
//  ParticleSystem.metal
//  AudioTest
//
//  GPU particle system: curl-noise advection in a compute kernel, point
//  rendering with additive glow. Audio drives field strength (bass),
//  emission rate (beat onsets), and hue (spectral centroid). Most appearance
//  parameters are exposed via uniforms so the test harness can tune them live.
//

#include <metal_stdlib>
using namespace metal;

struct Particle {
    float2 position;
    float2 velocity;
    float life;
    float seed;
};

struct ParticleUniforms {
    float emitterX;
    float emitterY;
    float deltaTime;
    float time;
    float fieldStrength;   // base field + bass contribution (computed on CPU)
    float emissionRate;    // base emission + beat contribution (computed on CPU)
    float hue;             // spectral-centroid hue, 0...1
    float hueShift;        // user hue offset
    float saturation;      // user color saturation
    float brightnessBoost; // user brightness multiplier
    float spawnRadius;     // emission disc radius
    float initialSpeed;    // outward burst speed at spawn
    float inertia;         // how quickly velocity follows the field (0...1)
    float lifeDecay;       // base aging rate
    float pointSize;       // base point size
    float speedToSize;     // extra point size per unit speed
    float scaleX;
    float scaleY;
    uint particleCount;
    uint frameSeed;
};

// --- Hash / noise helpers ---------------------------------------------------

static inline float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i + float2(0.0, 0.0));
    float b = hash12(i + float2(1.0, 0.0));
    float c = hash12(i + float2(0.0, 1.0));
    float d = hash12(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Scalar potential field; curl of it gives a divergence-free flow.
static inline float potential(float2 p, float t) {
    float n = valueNoise(p * 1.5 + float2(0.0, t * 0.10));
    n += 0.5 * valueNoise(p * 3.0 - float2(t * 0.15, 0.0));
    n += 0.25 * valueNoise(p * 6.0 + float2(t * 0.05, t * 0.05));
    return n;
}

static inline float2 curlNoise(float2 p, float t) {
    const float e = 0.01;
    float p_y1 = potential(p + float2(0.0, e), t);
    float p_y0 = potential(p - float2(0.0, e), t);
    float p_x1 = potential(p + float2(e, 0.0), t);
    float p_x0 = potential(p - float2(e, 0.0), t);
    float dPdy = (p_y1 - p_y0) / (2.0 * e);
    float dPdx = (p_x1 - p_x0) / (2.0 * e);
    return float2(dPdy, -dPdx);
}

static inline float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// --- Simulation -------------------------------------------------------------

kernel void updateParticles(device Particle *particles [[buffer(0)]],
                            constant ParticleUniforms &u [[buffer(1)]],
                            uint id [[thread_position_in_grid]]) {
    if (id >= u.particleCount) { return; }

    Particle p = particles[id];

    if (p.life <= 0.0) {
        // Dead particle: respawn with probability == emissionRate (beat-driven).
        float roll = hash12(float2(float(id) * 0.7351, float(u.frameSeed) * 1.373 + 0.5));
        if (roll < u.emissionRate) {
            float a = hash11(float(id) + float(u.frameSeed) * 0.013) * 6.2831853;
            // Outward burst velocity spreads new particles; sqrt() distributes
            // the spawn disc uniformly by area instead of bunching at center.
            float spd = u.initialSpeed * (0.3 + 0.7 * hash11(float(id) * 1.91 + u.time));
            float rad = u.spawnRadius * sqrt(hash11(float(id) * 3.17 + u.time));
            p.position = float2(u.emitterX, u.emitterY) + float2(cos(a), sin(a)) * rad;
            p.velocity = float2(cos(a), sin(a)) * spd;
            p.life = 1.0;
            p.seed = hash11(float(id) * 0.531 + float(u.frameSeed) * 0.027);
        } else {
            particles[id] = p;
            return;
        }
    }

    // Advect through the curl-noise field; bass scales the field strength.
    float2 field = curlNoise(p.position * 1.5, u.time) * u.fieldStrength;
    p.velocity = mix(p.velocity, field, clamp(u.inertia, 0.0, 1.0));
    p.position += p.velocity * u.deltaTime;

    // Age out; vary lifespan slightly per particle.
    p.life -= u.deltaTime * u.lifeDecay * (0.6 + 0.8 * p.seed);
    if (abs(p.position.x) > 1.3 || abs(p.position.y) > 1.3) {
        p.life = 0.0;
    }

    particles[id] = p;
}

// --- Rendering --------------------------------------------------------------

struct VSOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

vertex VSOut particleVertex(uint vid [[vertex_id]],
                            device const Particle *particles [[buffer(0)]],
                            constant ParticleUniforms &u [[buffer(1)]]) {
    Particle p = particles[vid];
    VSOut o;

    float2 clip = float2(p.position.x * u.scaleX, p.position.y * u.scaleY);
    o.position = float4(clip, 0.0, 1.0);

    float speed = length(p.velocity);
    float life = clamp(p.life, 0.0, 1.0);
    o.pointSize = (p.life > 0.0) ? (u.pointSize + speed * u.speedToSize) : 0.0;

    // Hue from spectral centroid + user shift, nudged by velocity direction.
    float ang = atan2(p.velocity.y, p.velocity.x) / 6.2831853; // -0.5...0.5
    float h = fract(u.hue + u.hueShift + 0.12 * ang);
    float bright = clamp(u.brightnessBoost * (0.25 + speed * 5.0), 0.0, 1.0) * life;
    float3 rgb = hsv2rgb(float3(h, clamp(u.saturation, 0.0, 1.0), bright));

    // Fade with remaining life for soft spawn/death.
    o.color = float4(rgb, life * 0.9);
    return o;
}

fragment float4 particleFragment(VSOut in [[stage_in]],
                                 float2 pc [[point_coord]]) {
    float d = length(pc - float2(0.5));
    float a = smoothstep(0.5, 0.0, d); // soft round falloff
    return float4(in.color.rgb * a, in.color.a * a);
}
