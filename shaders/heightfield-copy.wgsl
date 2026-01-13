struct CopyUniforms {
    resolution: vec2<f32>,
    padding: vec2<f32>,
};

@group(0) @binding(0) var<uniform> uniforms: CopyUniforms;
@group(0) @binding(1) var<storage, read> heightIn: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read_write> heightOut: array<vec4<f32>>;

@compute @workgroup_size(8, 8, 1)
fn cs_main(@builtin(global_invocation_id) id: vec3<u32>) {
    let width = i32(uniforms.resolution.x);
    let height = i32(uniforms.resolution.y);
    let x = i32(id.x);
    let z = i32(id.y);
    if (x >= width || z >= height) {
        return;
    }

    let index = u32(z * width + x);
    heightOut[index] = heightIn[index];
}
