struct BlurUniforms {
    resolution: vec2<f32>,
    direction: vec2<f32>,
};

@group(0) @binding(0) var blurSampler: sampler;
@group(0) @binding(1) var srcTex: texture_2d<f32>;
@group(0) @binding(2) var dstTex: texture_storage_2d<rgba16float, write>;
@group(0) @binding(3) var<uniform> uniforms: BlurUniforms;

@compute @workgroup_size(8, 8, 1)
fn cs_main(@builtin(global_invocation_id) id: vec3<u32>) {
    let width = u32(uniforms.resolution.x);
    let height = u32(uniforms.resolution.y);
    if (id.x >= width || id.y >= height) {
        return;
    }

    let uv = (vec2<f32>(f32(id.x) + 0.5, f32(id.y) + 0.5)) / uniforms.resolution;
    let texel = uniforms.direction / uniforms.resolution;

    let w0 = 0.227027;
    let w1 = 0.1945946;
    let w2 = 0.1216216;

    var color = textureSampleLevel(srcTex, blurSampler, uv, 0.0) * w0;
    color = color + textureSampleLevel(srcTex, blurSampler, uv + texel, 0.0) * w1;
    color = color + textureSampleLevel(srcTex, blurSampler, uv - texel, 0.0) * w1;
    color = color + textureSampleLevel(srcTex, blurSampler, uv + texel * 2.0, 0.0) * w2;
    color = color + textureSampleLevel(srcTex, blurSampler, uv - texel * 2.0, 0.0) * w2;

    textureStore(dstTex, vec2<i32>(i32(id.x), i32(id.y)), color);
}
