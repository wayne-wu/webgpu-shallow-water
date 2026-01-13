const EPS: f32 = 0.01;
const AMP: f32 = 0.005;
const FREQ: f32 = 20.0;
const AIR_IOR: f32 = 1.0;
const WATER_IOR: f32 = 1.33;

struct CausticsUniforms {
    params0: vec4<f32>, // time, heightRes.x, heightRes.y, causticsRes.x
    params1: vec4<f32>, // causticsRes.y, light1.xyz
    params2: vec4<f32>, // light2.xyz, padding
    params3: vec4<f32>, // light3.xyz, padding
};

@group(0) @binding(0) var<uniform> uniforms: CausticsUniforms;
@group(0) @binding(1) var<storage, read> heightData: array<vec4<f32>>;

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
    let t = x * x * sin(uniforms.params0.x) + z * z * sin(uniforms.params0.x);
    return AMP * (sin(FREQ * t) - cos((FREQ * 0.5) * t));
}

fn heightAtUV(uv: vec2<f32>) -> f32 {
    let res = uniforms.params0.yz;
    let resX = u32(res.x);
    let resY = u32(res.y);
    let uvClamped = clamp(uv, vec2<f32>(0.0), vec2<f32>(0.999999));
    let fx = uvClamped.x * (res.x - 1.0);
    let fz = uvClamped.y * (res.y - 1.0);
    let x0 = u32(floor(fx));
    let z0 = u32(floor(fz));
    let x1 = min(x0 + 1u, resX - 1u);
    let z1 = min(z0 + 1u, resY - 1u);
    let tx = fx - f32(x0);
    let tz = fz - f32(z0);
    let i00 = z0 * resX + x0;
    let i10 = z0 * resX + x1;
    let i01 = z1 * resX + x0;
    let i11 = z1 * resX + x1;
    let h00 = heightData[i00].z;
    let h10 = heightData[i10].z;
    let h01 = heightData[i01].z;
    let h11 = heightData[i11].z;
    let hx0 = mix(h00, h10, tx);
    let hx1 = mix(h01, h11, tx);
    return mix(hx0, hx1, tz);
}

fn height(x: f32, z: f32) -> f32 {
    let uv = (vec2<f32>(x, z) + vec2<f32>(1.0, 1.0)) * 0.5;
    return heightAtUV(uv);
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
    let worldSpacePos = vec3<f32>(position.x, 0.0, -position.y);
    let lightPos = uniforms.params3.xyz;
    out.startPos = remapCoordinate(worldSpacePos, lightPos);
    out.endPos = getEndPos(out.startPos, lightPos);
    return out;
}

@fragment
fn fs_main(input: VSOut) -> @location(0) vec4<f32> {
    let startArea = max(getArea(input.startPos), 1e-5);
    let endArea = max(getArea(input.endPos), 1e-5);
    let ratio = startArea / endArea;
    return vec4<f32>(ratio, 1.0, 1.0, 1.0);
}
