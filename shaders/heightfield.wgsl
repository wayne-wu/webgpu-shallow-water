const TIMESTEP: f32 = 0.5;
const HITRADIUS: f32 = 0.1;
const HITDEPTH: f32 = -0.09;

struct HeightUniforms {
    resolution: vec2<f32>,
    time: f32,
    mouseHit: u32,
    mousePos: vec2<f32>,
    screenRes: vec2<f32>,
    eyeCoordinate: vec3<f32>,
    padding: f32,
};

@group(0) @binding(0) var<uniform> uniforms: HeightUniforms;
@group(0) @binding(1) var heightSampler: sampler;
@group(0) @binding(2) var heightTexture: texture_2d<f32>;

struct VSOut {
    @builtin(position) position: vec4<f32>,
};

fn getCartesian(coord: vec3<f32>) -> vec3<f32> {
    let radius = coord.x;
    let phi = coord.y;
    let theta = coord.z;
    return vec3<f32>(
        radius * sin(phi) * cos(theta),
        radius * cos(phi),
        radius * sin(phi) * sin(theta)
    );
}

fn getRightVector(coord: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(sin(coord.z), 0.0, -cos(coord.z));
}

fn getMouseHitLocation() -> vec3<f32> {
    let eye = getCartesian(uniforms.eyeCoordinate);
    let focus = vec3<f32>(0.0, 0.0, 0.0);
    let forward = normalize(focus - eye);
    var right = normalize(getRightVector(uniforms.eyeCoordinate));
    let up = normalize(cross(right, forward));

    let f = 2.0;
    let u = (uniforms.mousePos.x * 2.0) / uniforms.screenRes.x - 1.0;
    let v = ((uniforms.screenRes.y - uniforms.mousePos.y) * 2.0) / uniforms.screenRes.y - 1.0;

    let ar = uniforms.screenRes.x / uniforms.screenRes.y;
    right = right * ar;

    let mouseP = eye + right * u + up * v + forward * f;
    let dir = normalize(mouseP - eye);
    let t = -mouseP.y / dir.y;
    return mouseP + t * dir;
}

fn withinRadius(uv: vec2<f32>) -> bool {
    let mouse = getMouseHitLocation();
    if (max(abs(mouse.x), abs(mouse.z)) > 1.0) {
        return false;
    }
    let mouseUV = (mouse.xz + vec2<f32>(1.0, 1.0)) * 0.5;
    return length(uv - mouseUV) < HITRADIUS;
}

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

    if (uniforms.mouseHit == 1u && withinRadius(uv)) {
        return vec4<f32>(0.0, 0.0, HITDEPTH, 0.0);
    }

    let du = textureSampleLevel(heightTexture, heightSampler, uv + eps.xy, 0.0).x -
             textureSampleLevel(heightTexture, heightSampler, uv - eps.xy, 0.0).x;
    let dw = textureSampleLevel(heightTexture, heightSampler, uv + eps.yx, 0.0).y -
             textureSampleLevel(heightTexture, heightSampler, uv - eps.yx, 0.0).y;

    let nVal = textureSampleLevel(heightTexture, heightSampler, uv + eps.yx, 0.0).z;
    let sVal = textureSampleLevel(heightTexture, heightSampler, uv - eps.yx, 0.0).z;
    let eVal = textureSampleLevel(heightTexture, heightSampler, uv + eps.xy, 0.0).z;
    let wVal = textureSampleLevel(heightTexture, heightSampler, uv - eps.xy, 0.0).z;

    let avg = (nVal + sVal + eVal + wVal) * 0.25;
    let blend = 0.5;
    var hVal = blend * avg + (1.0 - blend) * textureSampleLevel(heightTexture, heightSampler, uv, 0.0).z;
    hVal = hVal - TIMESTEP * (du + dw);

    let newSpeed = textureSampleLevel(heightTexture, heightSampler, uv, 0.0).xy;
    return vec4<f32>(newSpeed, 0.99 * hVal, 0.0);
}
