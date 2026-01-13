const EPS: f32 = 0.001;
const MAX_STEPS: u32 = 128u;
const SURFACE_STEPS: u32 = 256u;
const MAX_DIST: f32 = 20.0;
const TANK_HEIGHT: f32 = 0.5;
const AIR_IOR: f32 = 1.0;
const WATER_IOR: f32 = 1.33;
const WATER_TINT: vec3<f32> = vec3<f32>(0.1, 0.45, 0.65);

struct RenderUniforms {
    resolution: vec2<f32>,
    time: f32,
    padding0: f32,
    heightResolution: vec2<f32>,
    causticsEnabled: f32,
    causticsDebug: f32,
    eyeCoordinate: vec3<f32>,
    padding2: f32,
    lightPos: vec3<f32>,
    padding3: f32,
};

@group(0) @binding(0) var<uniform> uniforms: RenderUniforms;
@group(0) @binding(1) var<storage, read> heightData: array<vec4<f32>>;
@group(0) @binding(2) var causticsSampler: sampler;
@group(0) @binding(3) var causticsTexture: texture_2d<f32>;

struct VSOut {
    @builtin(position) position: vec4<f32>,
};

struct HitInfo {
    hit: u32,
    t: f32,
    position: vec3<f32>,
    normal: vec3<f32>,
};

fn distBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, vec3<f32>(0.0, 0.0, 0.0)));
}

fn boxNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec3<f32>(EPS, 0.0, 0.0);
    let d = vec3<f32>(
        distBox(p + e.xyy, vec3<f32>(1.0, TANK_HEIGHT, 1.0)) - distBox(p - e.xyy, vec3<f32>(1.0, TANK_HEIGHT, 1.0)),
        distBox(p + e.yxy, vec3<f32>(1.0, TANK_HEIGHT, 1.0)) - distBox(p - e.yxy, vec3<f32>(1.0, TANK_HEIGHT, 1.0)),
        distBox(p + e.yyx, vec3<f32>(1.0, TANK_HEIGHT, 1.0)) - distBox(p - e.yyx, vec3<f32>(1.0, TANK_HEIGHT, 1.0))
    );
    return normalize(d);
}

fn raymarchBox(eye: vec3<f32>, dir: vec3<f32>) -> HitInfo {
    var t = 0.0;
    let bounds = vec3<f32>(1.0, TANK_HEIGHT, 1.0);
    for (var i: u32 = 0u; i < MAX_STEPS; i = i + 1u) {
        let p = eye + dir * t;
        let d = distBox(p, bounds);
        if (d < EPS) {
            return HitInfo(1u, t, p, boxNormal(p));
        }
        t = t + d;
        if (t > MAX_DIST) {
            break;
        }
    }
    return HitInfo(0u, t, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0));
}

fn planeHit(eye: vec3<f32>, dir: vec3<f32>, planeY: f32) -> HitInfo {
    if (abs(dir.y) < 1e-4) {
        return HitInfo(0u, 0.0, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0));
    }
    let t = (planeY - eye.y) / dir.y;
    if (t <= 0.0) {
        return HitInfo(0u, t, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0));
    }
    let p = eye + dir * t;
    if (max(abs(p.x), abs(p.z)) > 1.0) {
        return HitInfo(0u, t, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0));
    }
    return HitInfo(1u, t, p, vec3<f32>(0.0, 1.0, 0.0));
}

fn getCartesian(sphericalCoord: vec3<f32>) -> vec3<f32> {
    let radius = sphericalCoord.x;
    let phi = sphericalCoord.y;
    let theta = sphericalCoord.z;
    return vec3<f32>(
        radius * sin(phi) * cos(theta),
        radius * cos(phi),
        radius * sin(phi) * sin(theta)
    );
}

fn getRightVector(coord: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(sin(coord.z), 0.0, -cos(coord.z));
}

fn refractDir(dir: vec3<f32>, n: vec3<f32>, eta: f32) -> vec3<f32> {
    let cosi = clamp(dot(-dir, n), -1.0, 1.0);
    let k = 1.0 - eta * eta * (1.0 - cosi * cosi);
    if (k < 0.0) {
        return reflect(dir, n);
    }
    return normalize(eta * dir + (eta * cosi - sqrt(k)) * n);
}

fn heightAtUV(uv: vec2<f32>) -> f32 {
    let res = uniforms.heightResolution;
    let uvClamped = clamp(uv, vec2<f32>(0.0), vec2<f32>(0.999999));
    let ix = u32(floor(uvClamped.x * res.x));
    let iz = u32(floor(uvClamped.y * res.y));
    let index = iz * u32(res.x) + ix;
    return heightData[index].z;
}

fn heightAtPos(p: vec3<f32>) -> f32 {
    let uv = (p.xz + vec2<f32>(1.0, 1.0)) * 0.5;
    return heightAtUV(uv);
}

fn fresnelSchlick(cosTheta: f32, f0: f32) -> f32 {
    return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
}

fn applyAbsorption(color: vec3<f32>, distance: f32) -> vec3<f32> {
    let absorb = exp(-distance * vec3<f32>(2.2, 0.9, 0.4));
    return mix(color, WATER_TINT, 0.25) * absorb;
}

fn checkerboard(p: vec3<f32>) -> vec3<f32> {
    let scale = 5.0;
    let cx = floor((p.x + 2.0) * scale);
    let cz = floor((p.z + 2.0) * scale);
    let checker = (i32(cx + cz) & 1) == 0;
    return select(vec3<f32>(0.4, 0.4, 0.4), vec3<f32>(0.9, 0.9, 0.95), checker);
}

fn surfaceNormal(p: vec3<f32>) -> vec3<f32> {
    let step = 2.0 / uniforms.heightResolution.x;
    let hL = heightAtPos(p - vec3<f32>(step, 0.0, 0.0));
    let hR = heightAtPos(p + vec3<f32>(step, 0.0, 0.0));
    let hD = heightAtPos(p - vec3<f32>(0.0, 0.0, step));
    let hU = heightAtPos(p + vec3<f32>(0.0, 0.0, step));
    let n = vec3<f32>(hL - hR, 2.0 * step, hD - hU);
    return normalize(n);
}

fn hitHeightfield(eye: vec3<f32>, dir: vec3<f32>) -> HitInfo {
    let step = 0.02;
    var t = 0.0;
    var prevDiff = 0.0;
    var hasPrev = false;

    for (var i: u32 = 0u; i < SURFACE_STEPS; i = i + 1u) {
        let p = eye + dir * t;
        if (t > MAX_DIST) {
            break;
        }
        if (abs(p.x) > 1.0 || abs(p.z) > 1.0 || p.y < -TANK_HEIGHT || p.y > 1.0) {
            t = t + step;
            continue;
        }

        let diff = p.y - heightAtPos(p);
        if (hasPrev && diff <= 0.0 && prevDiff > 0.0) {
            var tLow = t - step;
            var tHigh = t;
            for (var j: u32 = 0u; j < 6u; j = j + 1u) {
                let tMid = (tLow + tHigh) * 0.5;
                let pMid = eye + dir * tMid;
                let midDiff = pMid.y - heightAtPos(pMid);
                if (midDiff > 0.0) {
                    tLow = tMid;
                } else {
                    tHigh = tMid;
                }
            }
            let pHit = eye + dir * tHigh;
            return HitInfo(1u, tHigh, pHit, surfaceNormal(pHit));
        }

        prevDiff = diff;
        hasPrev = true;
        t = t + step;
    }

    return HitInfo(0u, t, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0));
}

fn shade(pos: vec3<f32>, normal: vec3<f32>, baseColor: vec3<f32>) -> vec4<f32> {
    let lightDir = normalize(uniforms.lightPos - pos);
    let diff = max(dot(normal, lightDir), 0.0);
    let color = baseColor * (0.2 + 0.8 * diff);
    return vec4<f32>(color, 1.0);
}

fn getCaustics(p: vec3<f32>) -> f32 {
    if (uniforms.causticsEnabled < 0.5) {
        return 0.0;
    }
    let uv = (p.xz + vec2<f32>(1.0, 1.0)) * 0.5;
    let c = textureSampleLevel(causticsTexture, causticsSampler, uv, 0.0).x;
    return c * c * c * 2.5;
}

fn hash12(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453);
}

@vertex
fn vs_main(@location(0) position: vec2<f32>) -> VSOut {
    var out: VSOut;
    out.position = vec4<f32>(position, 0.0, 1.0);
    return out;
}

@fragment
fn fs_main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
    if (uniforms.causticsDebug > 0.5) {
        let uv = fragCoord.xy / uniforms.resolution;
        let c = textureSampleLevel(causticsTexture, causticsSampler, uv, 0.0).x;
        return vec4<f32>(c, c, c, 1.0);
    }
    let eye = getCartesian(uniforms.eyeCoordinate);
    let focus = vec3<f32>(0.0, 0.0, 0.0);
    let forward = normalize(focus - eye);
    var right = normalize(getRightVector(uniforms.eyeCoordinate));
    let up = normalize(cross(right, forward));

    let jitter = vec2<f32>(
        hash12(fragCoord.xy + uniforms.time * 37.0),
        hash12(fragCoord.yx + uniforms.time * 83.0)
    ) - vec2<f32>(0.5, 0.5);
    let jittered = fragCoord.xy + jitter * 0.35;
    let u = jittered.x * 2.0 / uniforms.resolution.x - 1.0;
    let v = (uniforms.resolution.y - jittered.y) * 2.0 / uniforms.resolution.y - 1.0;
    let ar = uniforms.resolution.x / uniforms.resolution.y;
    right = right * ar;

    let imagePos = eye + right * u + up * v + forward * 2.0;
    let dir = normalize(imagePos - eye);

    let surfaceHit = hitHeightfield(eye, dir);
    let boxHit = raymarchBox(eye, dir);
    let floorHit = planeHit(eye, dir, -TANK_HEIGHT);

    let sideHeight = heightAtPos(boxHit.position);
    let boxIsSide = boxHit.hit == 1u &&
        abs(boxHit.normal.y) < 0.5 &&
        boxHit.position.y <= sideHeight + EPS;
    if (surfaceHit.hit == 1u && (floorHit.hit == 0u || surfaceHit.t < floorHit.t) && (!boxIsSide || surfaceHit.t < boxHit.t)) {
        var eta = AIR_IOR / WATER_IOR;
        let refrDir = refractDir(dir, surfaceHit.normal, eta);
        let innerStart = surfaceHit.position + refrDir * (EPS * 4.0);
        let innerFloorHit = planeHit(innerStart, refrDir, -TANK_HEIGHT);
        let cosTheta = clamp(dot(-dir, surfaceHit.normal), 0.0, 1.0);
        eta = (AIR_IOR - WATER_IOR) / (AIR_IOR + WATER_IOR);
        let f0 = eta * eta;
        let fresnel = fresnelSchlick(cosTheta, f0);
        let reflectColor = vec3<f32>(0.9, 0.9, 0.95);

        var refracted = WATER_TINT;
        if (innerFloorHit.hit == 1u) {
            let base = checkerboard(innerFloorHit.position);
            let caustics = getCaustics(innerFloorHit.position);
            var color = shade(innerFloorHit.position, innerFloorHit.normal, base).rgb;
            let causticTint = vec3<f32>(1.0, 0.9, 0.6) * caustics;
            color = mix(color, color + causticTint, 0.35);
            let travel = innerFloorHit.t;
            refracted = applyAbsorption(color, travel);
        }

        let wave = heightAtPos(surfaceHit.position);
        let surfaceTint = mix(vec3<f32>(0.05, 0.25, 0.45), vec3<f32>(0.2, 0.6, 0.9), clamp(wave * 12.0, 0.0, 1.0));
        let surfaceLit = shade(surfaceHit.position, surfaceHit.normal, surfaceTint).rgb;
        let mixed = mix(refracted, reflectColor, fresnel);
        var finalColor = mix(mixed, surfaceLit, 0.2);
        let edge = 1.0 - max(abs(surfaceHit.position.x), abs(surfaceHit.position.z));
        let feather = smoothstep(0.0, 0.03, edge);
        let background = vec3<f32>(0.9, 0.9, 0.95);
        finalColor = mix(background, finalColor, feather);
        return vec4<f32>(finalColor, 1.0);
    }

    if (boxIsSide && (floorHit.hit == 0u || boxHit.t < floorHit.t)) {
        var eta = AIR_IOR / WATER_IOR;
        let refrDir = refractDir(dir, boxHit.normal, eta);
        let innerStart = boxHit.position + refrDir * (EPS * 4.0);
        let innerFloorHit = planeHit(innerStart, refrDir, -TANK_HEIGHT);
        let cosTheta = clamp(dot(-dir, boxHit.normal), 0.0, 1.0);
        eta = (AIR_IOR - WATER_IOR) / (AIR_IOR + WATER_IOR);
        let f0 = eta * eta;
        let fresnel = fresnelSchlick(cosTheta, f0);
        let reflectColor = vec3<f32>(0.9, 0.9, 0.95);

        var refracted = WATER_TINT;
        if (innerFloorHit.hit == 1u) {
            let base = checkerboard(innerFloorHit.position);
            let caustics = getCaustics(innerFloorHit.position);
            var color = shade(innerFloorHit.position, innerFloorHit.normal, base).rgb;
            let causticTint = vec3<f32>(1.0, 0.9, 0.6) * caustics;
            color = mix(color, color + causticTint, 0.35);
            refracted = applyAbsorption(color, innerFloorHit.t);
        }

        let mixed = mix(refracted, reflectColor, fresnel);
        return vec4<f32>(mixed, 1.0);
    }

    if (floorHit.hit == 1u) {
        let base = checkerboard(floorHit.position);
        let caustics = getCaustics(floorHit.position);
        var color = shade(floorHit.position, floorHit.normal, base).rgb;
        let causticTint = vec3<f32>(1.0, 0.9, 0.6) * caustics;
        color = mix(color, color + causticTint, 0.35);
        return vec4<f32>(color, 1.0);
    }

    return vec4<f32>(0.9, 0.9, 0.95, 1.0);
}
