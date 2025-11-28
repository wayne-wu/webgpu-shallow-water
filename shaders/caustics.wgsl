const EPS: f32 = 0.01;
const AMP: f32 = 0.005;
const FREQ: f32 = 20.0;
const AIR_IOR: f32 = 1.0;
const WATER_IOR: f32 = 1.33;

struct CausticsUniforms {
    time: f32,
    padding0: vec3<f32>,
    light1: vec3<f32>,
    padding1: f32,
    light2: vec3<f32>,
    padding2: f32,
    light3: vec3<f32>,
    padding3: f32,
};

@group(0) @binding(0) var<uniform> uniforms: CausticsUniforms;
@group(0) @binding(1) var heightSampler: sampler;
@group(0) @binding(2) var heightTexture: texture_2d<f32>;

struct VSOut {
    @builtin(position) position: vec4<f32>,
    @location(0) startPos: vec3<f32>,
    @location(1) endPos: vec3<f32>,
};

fn distBox(p: vec3<f32>) -> f32 {
    let b = vec3<f32>(1.0, 1.0, 1.0);
    let d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, vec3<f32>(0.0, 0.0, 0.0)));
}

fn sinusoid(x: f32, z: f32) -> f32 {
    let t = x * x * sin(uniforms.time) + z * z * sin(uniforms.time);
    return AMP * (sin(FREQ * t) - cos((FREQ * 0.5) * t));
}

fn height(x: f32, z: f32) -> f32 {
    let uv = (vec2<f32>(x, z) + vec2<f32>(1.0, 1.0)) * 0.5;
    return textureSampleLevel(heightTexture, heightSampler, uv, 0.0).z;
}

fn getSurfaceNormal(p: vec3<f32>) -> vec3<f32> {
    let n = vec3<f32>(
        height(p.x - EPS, p.z) - height(p.x + EPS, p.z),
        2.0 * EPS,
        height(p.x, p.z - EPS) - height(p.x, p.z + EPS)
    );
    return normalize(n);
}

fn getRefractedDir(dir: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    let costheta = dot(dir, -n);
    let ratio = AIR_IOR / WATER_IOR;
    let c = ratio * ratio * (1.0 - costheta * costheta);
    return ratio * dir + (ratio * costheta - sqrt(1.0 - c)) * n;
}

fn getEndPos(startPos: vec3<f32>, lightPos: vec3<f32>) -> vec3<f32> {
    var dir = normalize(startPos - lightPos);
    var p = startPos;
    var hitBox = false;

    for (var i: u32 = 0u; i < 50u; i = i + 1u) {
        let d = distBox(p);
        if (d < EPS) {
            hitBox = true;
            break;
        }
        p = p + dir * d;
    }

    if (!hitBox) {
        return startPos;
    }

    let t = -p.y / dir.y;
    p = p + t * dir;

    dir = normalize(getRefractedDir(dir, getSurfaceNormal(p)));
    let tFloor = (-1.0 - p.y) / dir.y;
    p = p + tFloor * dir;
    return p;
}

fn remapCoordinate(pos: vec3<f32>, lightPos: vec3<f32>) -> vec3<f32> {
    let dir = normalize(pos - lightPos);
    let t = (1.5 - lightPos.y) / dir.y;
    return lightPos + t * dir;
}

fn getArea(pos: vec3<f32>) -> f32 {
    return length(dpdx(pos)) * length(dpdy(pos));
}

@vertex
fn vs_main(@location(0) position: vec2<f32>) -> VSOut {
    var out: VSOut;
    out.position = vec4<f32>(position, 0.0, 1.0);
    let worldSpacePos = vec3<f32>(position.x, 0.0, position.y);
    out.startPos = remapCoordinate(worldSpacePos, uniforms.light3).xzy;
    out.endPos = getEndPos(out.startPos, uniforms.light3).xzy;
    out.startPos = out.startPos.xzy;
    return out;
}

@fragment
fn fs_main(input: VSOut) -> @location(0) vec4<f32> {
    let startArea = max(getArea(input.startPos), 1e-5);
    let endArea = max(getArea(input.endPos), 1e-5);
    return vec4<f32>(startArea / endArea, 1.0, 1.0, 1.0);
}
