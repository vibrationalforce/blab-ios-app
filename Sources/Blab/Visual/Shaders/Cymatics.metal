//
//  Cymatics.metal
//  BLAB
//
//  Cymatics visualization shader
//  Creates water-like patterns driven by FFT audio data
//  Bio-reactive color mapping (HRV Coherence → Hue)
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex Shader

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut cymatics_vertex(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}


// MARK: - Fragment Shader Uniforms

struct CymaticsUniforms {
    float time;              // Time in seconds
    float audioLevel;        // Audio amplitude (0.0 - 1.0)
    float frequency;         // Dominant frequency (Hz)
    float hrvCoherence;      // HRV coherence (0.0 - 1.0)
    float heartRate;         // Heart rate (BPM)
    float2 resolution;       // Screen resolution
    float waveSpeed;         // Wave propagation speed
    float waveAmplitude;     // Wave amplitude multiplier
};


// MARK: - Helper Functions

/// Hash function for noise generation
float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

/// Smoothed noise
float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);  // Smoothstep

    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

/// Fractal Brownian Motion (layered noise)
float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }

    return value;
}

/// Convert HSV to RGB
float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}


// MARK: - Cymatics Pattern Generation

/// Generate Chladni plate-like patterns
float chladniPattern(float2 uv, float frequency, float time) {
    // Multiple wave interference patterns
    float pattern = 0.0;

    // Wave 1: Horizontal
    float wave1 = sin(uv.x * frequency + time);

    // Wave 2: Vertical
    float wave2 = sin(uv.y * frequency + time * 0.7);

    // Wave 3: Diagonal
    float wave3 = sin((uv.x + uv.y) * frequency * 0.5 + time * 1.3);

    // Wave 4: Radial
    float2 center = uv - 0.5;
    float radius = length(center);
    float wave4 = sin(radius * frequency * 2.0 + time * 0.5);

    // Combine waves with interference
    pattern = (wave1 + wave2 + wave3 + wave4) * 0.25;

    // Add nodal lines (Chladni patterns)
    pattern = abs(pattern);
    pattern = smoothstep(0.0, 0.1, pattern);
    pattern = 1.0 - pattern;

    return pattern;
}

/// Water ripple effect
float waterRipple(float2 uv, float time, float audioLevel) {
    float2 center = uv - 0.5;
    float dist = length(center);

    // Multiple ripples at different speeds
    float ripple1 = sin(dist * 30.0 - time * 2.0);
    float ripple2 = sin(dist * 20.0 - time * 1.5);
    float ripple3 = sin(dist * 40.0 - time * 3.0);

    // Combine ripples
    float ripple = (ripple1 + ripple2 + ripple3) / 3.0;

    // Modulate by audio level
    ripple *= audioLevel * 0.5 + 0.5;

    // Fade at edges
    ripple *= smoothstep(0.7, 0.0, dist);

    return ripple * 0.5 + 0.5;
}


// MARK: - Main Fragment Shader

fragment float4 cymatics_fragment(
    VertexOut in [[stage_in]],
    constant CymaticsUniforms &uniforms [[buffer(0)]]
) {
    // Normalize coordinates (0 to 1)
    float2 uv = in.texCoord;

    // Aspect-corrected coordinates (centered)
    float aspect = uniforms.resolution.x / uniforms.resolution.y;
    float2 centeredUV = (uv - 0.5) * float2(aspect, 1.0) + 0.5;


    // MARK: - Pattern Generation

    // Frequency mapping (audio → visual frequency)
    float visualFreq = uniforms.frequency / 100.0;  // Scale down for visual
    visualFreq = clamp(visualFreq, 5.0, 50.0);  // 5-50 for good patterns

    // Generate Chladni pattern
    float chladni = chladniPattern(centeredUV, visualFreq, uniforms.time * uniforms.waveSpeed);

    // Generate water ripples
    float ripple = waterRipple(centeredUV, uniforms.time, uniforms.audioLevel);

    // Combine patterns based on audio level
    float pattern = mix(chladni, ripple, uniforms.audioLevel);

    // Add noise for texture
    float noiseValue = fbm(centeredUV * 5.0 + uniforms.time * 0.1);
    pattern += noiseValue * 0.1;

    // Modulate by audio level (pulsing effect)
    pattern *= (1.0 + uniforms.audioLevel * uniforms.waveAmplitude);


    // MARK: - Bio-Reactive Coloring

    // HRV Coherence → Hue
    // 0.0-0.4: Red (stressed)
    // 0.4-0.6: Yellow (transitional)
    // 0.6-1.0: Green-Cyan (coherent/flow state)
    float hue = uniforms.hrvCoherence * 0.5;  // 0.0 (red) to 0.5 (cyan)

    // Heart Rate → Color shift speed
    float heartRateNorm = (uniforms.heartRate - 40.0) / 80.0;  // Normalize 40-120 BPM
    hue += sin(uniforms.time * heartRateNorm * 2.0) * 0.1;  // Oscillate hue

    // Pattern intensity → Saturation & Brightness
    float saturation = 0.6 + pattern * 0.4;  // 0.6-1.0
    float brightness = 0.3 + pattern * 0.7;   // 0.3-1.0

    // Convert HSV to RGB
    float3 color = hsv2rgb(float3(hue, saturation, brightness));


    // MARK: - Post-Processing

    // Add glow effect
    float glow = smoothstep(0.3, 1.0, pattern) * uniforms.audioLevel;
    color += glow * float3(0.3, 0.5, 0.8);  // Cyan glow

    // Vignette effect (darker at edges)
    float2 vignetteUV = centeredUV - 0.5;
    float vignette = 1.0 - length(vignetteUV) * 0.5;
    vignette = smoothstep(0.3, 1.0, vignette);
    color *= vignette;

    // Clamp color
    color = clamp(color, 0.0, 1.0);


    // MARK: - Final Output

    return float4(color, 1.0);
}


// MARK: - Alternative: Particle Field Shader

fragment float4 particle_fragment(
    VertexOut in [[stage_in]],
    constant CymaticsUniforms &uniforms [[buffer(0)]]
) {
    float2 uv = in.texCoord;
    float aspect = uniforms.resolution.x / uniforms.resolution.y;
    float2 centeredUV = (uv - 0.5) * float2(aspect, 1.0) + 0.5;

    // Generate particle-like patterns
    float particles = 0.0;

    for (int i = 0; i < 8; i++) {
        float2 offset = float2(
            sin(uniforms.time * (float(i) * 0.3 + 1.0)),
            cos(uniforms.time * (float(i) * 0.4 + 1.0))
        ) * 0.3;

        float2 particlePos = centeredUV + offset;
        float dist = length(particlePos - 0.5);

        // Particle glow
        float particle = 1.0 / (dist * 50.0 + 1.0);
        particles += particle;
    }

    particles *= uniforms.audioLevel * 2.0;

    // Color based on HRV
    float hue = uniforms.hrvCoherence * 0.5;
    float3 color = hsv2rgb(float3(hue, 0.8, particles));

    return float4(color, 1.0);
}
