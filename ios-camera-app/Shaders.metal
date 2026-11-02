//
//  Shaders.metal
//  ios-camera-app
//
//  Metal Shading Language shaders ported from recovered GLSL shaders in
//  com.oplus.camera.gl (GLImageView.java, i.java):
//  - vertex_pass_through — full-screen quad
//  - fragment_color_cube — LUT color grading (CIColorCube equivalent)
//  - fragment_color_controls — brightness/contrast/saturation
//  - fragment_temperature_tint — white balance temperature + tint
//  - fragment_sharpen — luminance sharpening
//  - fragment_film_grain — film grain overlay
//

#include <metal_stdlib>
using namespace metal;

// Vertex structure
struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord   [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Full-screen quad vertex shader
vertex VertexOut vertex_pass_through(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

// Fragment: LUT color cube (CIColorCube equivalent)
fragment float4 fragment_color_cube(VertexOut in [[stage_in]],
                                    texture2d<float> sTexture [[texture(0)]],
                                    texture2d<float> sLUT [[texture(1)]],
                                    constant float &intensity [[buffer(0)]]) {
    constexpr sampler sSampler(mag_filter::linear, min_filter::linear);
    constexpr sampler lutSampler(mag_filter::linear, min_filter::linear);

    float4 color = sTexture.sample(sSampler, in.texCoord);

    // Sample LUT texture (3D LUT encoded as 2D)
    float3 lutCoord = color.rgb;
    float4 lutColor = sLUT.sample(lutSampler, lutCoord.xy);

    // Simple 1D LUT approximation — in production, use a proper 3D LUT texture
    float3 result = mix(color.rgb, lutColor.rgb, intensity);

    return float4(result, color.a);
}

// Fragment: Color controls (brightness, contrast, saturation)
fragment float4 fragment_color_controls(VertexOut in [[stage_in]],
                                        texture2d<float> sTexture [[texture(0)]],
                                        constant float &params [[buffer(0)]]) {
    constexpr sampler sSampler(mag_filter::linear, min_filter::linear);

    float4 color = sTexture.sample(sSampler, in.texCoord);

    float brightness = params[0];
    float contrast   = params[1];
    float saturation = params[2];

    // Brightness
    color.rgb += brightness;

    // Contrast (pivot around 0.5)
    color.rgb = (color.rgb - 0.5) * contrast + 0.5;

    // Saturation (luminance-based)
    float luminance = dot(color.rgb, float3(0.299, 0.587, 0.114));
    color.rgb = mix(float3(luminance), color.rgb, saturation);

    // Clamp
    color.rgb = clamp(color.rgb, 0.0, 1.0);

    return color;
}

// Fragment: Temperature + Tint (white balance)
fragment float4 fragment_temperature_tint(VertexOut in [[stage_in]],
                                          texture2d<float> sTexture [[texture(0)]],
                                          constant float &params [[buffer(0)]]) {
    constexpr sampler sSampler(mag_filter::linear, min_filter::linear);

    float4 color = sTexture.sample(sSampler, in.texCoord);

    float temp = params[0];  // temperature deviation from 6500K
    float tint = params[1];  // tint deviation

    // Temperature: blue ↔ yellow
    float3 tempShift = float3(-temp * 0.15, 0.0, temp * 0.1);
    color.rgb += tempShift;

    // Tint: green ↔ magenta
    float3 tintShift = float3(tint * 0.05, -tint * 0.1, tint * 0.05);
    color.rgb += tintShift;

    // Clamp
    color.rgb = clamp(color.rgb, 0.0, 1.0);

    return color;
}

// Fragment: Sharpen luminance
fragment float4 fragment_sharpen(VertexOut in [[stage_in]],
                                 texture2d<float> sTexture [[texture(0)]],
                                 constant float &sharpness [[buffer(0)]]) {
    constexpr sampler sSampler(mag_filter::linear, min_filter::linear);

    float4 color = sTexture.sample(sSampler, in.texCoord);

    // Simple unsharp mask using neighboring texels
    float2 onePixel = float2(1.0 / 1920.0, 1.0 / 1080.0);  // approximate
    float4 neighbors = float4(
        sTexture.sample(sSampler, in.texCoord + float2(-onePixel.x, 0.0)),
        sTexture.sample(sSampler, in.texCoord + float2(onePixel.x, 0.0))
    );

    float4 blurred = (color + neighbors.x + neighbors.z) / 3.0;
    float4 detail = color - blurred;
    color.rgb += detail.rgb * sharpness * 0.5;

    // Clamp
    color.rgb = clamp(color.rgb, 0.0, 1.0);

    return color;
}

// Fragment: Film grain overlay
fragment float4 fragment_film_grain(VertexOut in [[stage_in]],
                                    texture2d<float> sTexture [[texture(0)]],
                                    constant float &intensity [[buffer(0)]]) {
    constexpr sampler sSampler(mag_filter::linear, min_filter::linear);

    float4 color = sTexture.sample(sSampler, in.texCoord);

    // Simple pseudo-random noise
    float2 uv = in.texCoord * float2(100.0, 100.0);
    float noise = fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
    float3 grain = float3(noise, noise, noise) * intensity * 0.1;

    color.rgb += grain;
    color.rgb = clamp(color.rgb, 0.0, 1.0);

    return color;
}
