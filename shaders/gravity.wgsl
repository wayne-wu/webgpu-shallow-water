const TIMESTEP: f32 = 0.5;

struct GravityUniforms {
    resolution: vec2<f32>,
    padding: vec2<f32>,
};

@group(0) @binding(0) var<uniform> uniforms: GravityUniforms;
@group(0) @binding(1) var heightSampler: sampler;
@group(0) @binding(2) var heightTexture: texture_2d<f32>;

struct VSOut {
    @builtin(position) position: vec4<f32>,
};

@vertex
fn vs_main(@location(0) position: vec2<f32>) -> VSOut {
    var out: VSOut;
    out.position = vec4<f32>(position, 0.0, 1.0);
    return out;
}

@fragment
fn fs_main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
    let uv = fragCoord.xy / uniforms.resolution;
    let h = 1.0 / uniforms.resolution.x;
    let eps = vec2<f32>(h, 0.0);

    let dhdx = textureSampleLevel(heightTexture, heightSampler, uv + eps.xy, 0.0).z -
               textureSampleLevel(heightTexture, heightSampler, uv - eps.xy, 0.0).z;
    let dhdz = textureSampleLevel(heightTexture, heightSampler, uv + eps.yx, 0.0).z -
               textureSampleLevel(heightTexture, heightSampler, uv - eps.yx, 0.0).z;
    let delh = vec2<f32>(dhdx, dhdz);

    var v = textureSampleLevel(heightTexture, heightSampler, uv, 0.0).xy - TIMESTEP * delh;
    let heightVal = textureSampleLevel(heightTexture, heightSampler, uv, 0.0).z;

    if (fragCoord.x <= 1.5) {
        v.x = 0.9 * abs(v.x);
    }
    if (fragCoord.y <= 1.5) {
        v.y = 0.9 * abs(v.y);
    }
    if (fragCoord.x >= uniforms.resolution.x - 1.5) {
        v.x = 0.9 * -abs(v.x);
    }
    if (fragCoord.y >= uniforms.resolution.y - 1.5) {
        v.y = 0.9 * -abs(v.y);
    }

    return vec4<f32>(v, heightVal, 0.0);
}
