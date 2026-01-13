const PI: f32 = 3.14159265;
const BOUNDS: f32 = 2.0;

struct HeightUniforms {
    resolution: vec2<f32>,
    mousePos: vec2<f32>,
    mouseParams: vec4<f32>, // mouseSpeed, mouseSize, mouseDeep, viscosity
};

@group(0) @binding(0) var<uniform> uniforms: HeightUniforms;
@group(0) @binding(1) var<storage, read> heightIn: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read_write> heightOut: array<vec4<f32>>;

fn heightAt(ix: i32, iz: i32, width: i32, height: i32) -> vec4<f32> {
    let x = clamp(ix, 0, width - 1);
    let z = clamp(iz, 0, height - 1);
    let index = u32(z * width + x);
    return heightIn[index];
}

@compute @workgroup_size(8, 8, 1)
fn cs_main(@builtin(global_invocation_id) id: vec3<u32>) {
    let width = i32(uniforms.resolution.x);
    let height = i32(uniforms.resolution.y);
    let x = i32(id.x);
    let z = i32(id.y);
    if (x >= width || z >= height) {
        return;
    }

    let center = heightAt(x, z, width, height);
    let nVal = heightAt(x, z + 1, width, height).z;
    let sVal = heightAt(x, z - 1, width, height).z;
    let eVal = heightAt(x + 1, z, width, height).z;
    let wVal = heightAt(x - 1, z, width, height).z;

    let neighborHeight = (nVal + sVal + eVal + wVal) * 0.5 - center.w;
    var newHeight = neighborHeight * uniforms.mouseParams.w;

    let grid = vec2<f32>((f32(x) + 0.5) / uniforms.resolution.x, (f32(z) + 0.5) / uniforms.resolution.y);
    let centerVec = vec2<f32>(0.5, 0.5);
    let offset = (grid - centerVec) * BOUNDS - uniforms.mousePos;
    let mousePhase = clamp(length(offset) * PI / uniforms.mouseParams.y, 0.0, PI);
    let mouseImpact = (cos(mousePhase) + 1.0) * uniforms.mouseParams.z * uniforms.mouseParams.x;
    newHeight = newHeight + mouseImpact;
    newHeight = clamp(newHeight, -0.12, 0.12);

    let index = u32(z * width + x);
    heightOut[index] = vec4<f32>(0.0, 0.0, newHeight, center.z);
}
