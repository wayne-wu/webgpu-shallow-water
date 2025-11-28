const EPS: f32 = 0.001;
const STEPSIZE: f32 = 0.001;
const MAXSTEPS: u32 = 1000u;
const FREQ: f32 = 20.0;
const AMP: f32 = 0.005;
const OVERSTEP: f32 = 4.0;
const AIR_IOR: f32 = 1.0;
const WATER_IOR: f32 = 1.33;
const TANK_HEIGHT: f32 = 0.5;
const BBOX_HEIGHT: f32 = 0.1;
const FLOOR_WIDTH: f32 = 2.0;

struct RenderUniforms {
    resolution: vec2<f32>,
    time: f32,
    padding0: f32,
    eyeCoordinate: vec3<f32>,
    padding1: f32,
    light1: vec3<f32>,
    padding2: f32,
    light2: vec3<f32>,
    padding3: f32,
    light3: vec3<f32>,
    padding4: f32,
};

@group(0) @binding(0) var<uniform> uniforms: RenderUniforms;
@group(0) @binding(1) var linearSampler: sampler;
@group(0) @binding(2) var heightTexture: texture_2d<f32>;
@group(0) @binding(4) var causticsTexture: texture_2d<f32>;
@group(0) @binding(5) var skyTexture: texture_2d<f32>;

struct VSOut {
    @builtin(position) position: vec4<f32>,
};

fn distBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, vec3<f32>(0.0, 0.0, 0.0)));
}

fn distBoxDefault(p: vec3<f32>) -> f32 {
    return distBox(p, vec3<f32>(1.0, TANK_HEIGHT, 1.0));
}

fn distWaveBbox(p: vec3<f32>) -> f32 {
    return distBox(p, vec3<f32>(1.0, BBOX_HEIGHT, 1.0));
}

fn sinusoid(x: f32, z: f32) -> f32 {
    let t = x * x * sin(uniforms.time) + z * z * sin(uniforms.time);
    return AMP * (sin(FREQ * t) - cos((FREQ * 0.5) * t));
}

fn heightAt(x: f32, z: f32) -> f32 {
    let uv = (vec2<f32>(x, z) + vec2<f32>(1.0, 1.0)) * 0.5;
    return textureSampleLevel(heightTexture, linearSampler, uv, 0.0).z;
}

fn heightAtP(p: vec3<f32>) -> f32 {
    return heightAt(p.x, p.z);
}

fn frac(x: f32) -> f32 {
    return x - floor(x);
}

fn getBoxNormal(p: vec3<f32>) -> vec3<f32> {
    let n = vec3<f32>(
        distBoxDefault(p + vec3<f32>(EPS, 0.0, 0.0)) - distBoxDefault(p),
        distBoxDefault(p + vec3<f32>(0.0, EPS, 0.0)) - distBoxDefault(p),
        distBoxDefault(p + vec3<f32>(0.0, 0.0, EPS)) - distBoxDefault(p)
    );
    return normalize(n);
}

fn getSurfaceNormal(p: vec3<f32>) -> vec3<f32> {
    let n = vec3<f32>(
        heightAt(p.x - EPS, p.z) - heightAt(p.x + EPS, p.z),
        2.0 * EPS,
        heightAt(p.x, p.z - EPS) - heightAt(p.x, p.z + EPS)
    );
    return normalize(n);
}

fn getCaustics(p: vec3<f32>) -> f32 {
    let uv = (p.xz + vec2<f32>(1.0, 1.0)) * 0.5;
    let caustics = textureSampleLevel(causticsTexture, linearSampler, uv, 0.0);
    let intensity = caustics.x;
    return pow(intensity, 1.0) * 5.0;
}

fn getCheckerBoard(p: vec3<f32>) -> vec4<f32> {
    let numTiles = 40.0;
    let x = floor((p.x + 2.0) * 0.25 * numTiles);
    let y = floor((p.y + 2.0) * 0.25 * numTiles);
    let z = floor((p.z + 2.0) * 0.25 * numTiles);
    var isSame = (frac(x * 0.5) < EPS) == (frac(z * 0.5) < EPS);
    if (isSame) {
        isSame = (frac(y * 0.5) < EPS);
    } else {
        isSame = !isSame;
    }
    return select(vec4<f32>(0.9, 0.9, 0.9, 1.0), vec4<f32>(0.1, 0.1, 0.1, 1.0), isSame);
}

fn getCheckerBoardFlat(p: vec3<f32>) -> vec4<f32> {
    let numTiles = 40.0;
    let x = floor((p.x + 2.0) * 0.25 * numTiles);
    let z = floor((p.z + 2.0) * 0.25 * numTiles);
    let isSame = (frac(x * 0.5) < EPS) == (frac(z * 0.5) < EPS);
    return select(vec4<f32>(0.9, 0.9, 0.9, 1.0), vec4<f32>(0.1, 0.1, 0.1, 1.0), isSame);
}

fn getPic(p: vec3<f32>, tex: texture_2d<f32>) -> vec4<f32> {
    let uv = (p.xz + vec2<f32>(1.0, 1.0)) * 0.5;
    return textureSampleLevel(tex, linearSampler, uv, 0.0);
}

fn reflection(v: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    return -v + 2.0 * dot(v, n) * n;
}

fn intensity(eye: vec3<f32>, p: vec3<f32>, n: vec3<f32>, kSpec: f32, specWeight: f32, diffWeight: f32) -> f32 {
    var toLight = normalize(uniforms.light1 - p);
    let toEye = normalize(eye - p);
    var refDir = normalize(reflection(toLight, n));

    var diffuse = max(0.0, dot(toLight, n));
    var specular = pow(max(dot(refDir, toEye), 0.0), kSpec);

    toLight = normalize(uniforms.light2 - p);
    refDir = normalize(reflection(toLight, n));
    diffuse += max(0.0, dot(toLight, refDir));
    specular += pow(max(dot(refDir, toEye), 0.0), kSpec);

    toLight = normalize(uniforms.light3 - p);
    refDir = normalize(reflection(toLight, n));
    diffuse += max(0.0, dot(toLight, refDir));
    specular += pow(max(dot(refDir, toEye), 0.0), kSpec);

    return specWeight * specular + diffWeight * diffuse;
}

fn getRefractedDir(dir: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    let costheta = dot(dir, -n);
    let ratio = AIR_IOR / WATER_IOR;
    let c = ratio * ratio * (1.0 - costheta * costheta);
    return ratio * dir + (ratio * costheta - sqrt(1.0 - c)) * n;
}

fn shadeWall(eye: vec3<f32>, p: vec3<f32>, normal: vec3<f32>) -> vec4<f32> {
    return 0.5 * intensity(eye, p, normal, 0.0, 0.0, 1.0) * getCheckerBoard(p);
}

fn shadeFloor(eye: vec3<f32>, p: vec3<f32>) -> vec4<f32> {
    return 0.5 * intensity(eye, p, vec3<f32>(0.0, 1.0, 0.0), 0.0, 0.0, 1.0) * getCheckerBoardFlat(p);
}

fn shadeSky(p: vec3<f32>) -> vec4<f32> {
    return getPic(p, skyTexture);
}

fn shadeWater(eye: vec3<f32>, p: vec3<f32>, normal: vec3<f32>) -> vec4<f32> {
    return intensity(eye, p, normal, 50.0, 2.0, 0.0) * vec4<f32>(1.0, 1.0, 1.0, 1.0);
}

fn getFresnel(n: vec3<f32>, eye: vec3<f32>, p: vec3<f32>) -> f32 {
    let toEye = normalize(eye - p);
    return dot(n, toEye);
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

fn outOfBox(p: vec3<f32>) -> bool {
    return max(abs(p.x), abs(p.z)) > 1.0;
}

fn hitFloor(p: vec3<f32>, dir: vec3<f32>, floorPos: ptr<function, vec3<f32>>) -> bool {
    let t = (-TANK_HEIGHT - p.y) / dir.y;
    (*floorPos) = p + t * dir;
    return max(abs((*floorPos).x), abs((*floorPos).z)) < FLOOR_WIDTH;
}

fn hitBox(p: ptr<function,vec3<f32>>, dir: vec3<f32>) -> bool {
    for (var i: u32 = 0u; i < 50u; i = i + 1u) {
        let current = *p;
        var d: f32;
        if (current.y < heightAtP(current)) {
            d = distBoxDefault(current);
        }
        else {
            d = distWaveBbox(current);
        }
        if (d < EPS) {
            return true;
        }
        *p = current + dir * d;
    }
    return false;
}

fn hitSurface(dir: vec3<f32>, eye: vec3<f32>, p: ptr<function, vec3<f32>>, surfaceColor: ptr<function, vec4<f32>>, invertNormal: bool) -> bool {
    for (var i: u32 = 0u; i < MAXSTEPS; i = i + 1u) {
        let current = *p;
        if (current.y < heightAtP(current)) {
            let n = select(getSurfaceNormal(current), -getSurfaceNormal(current), invertNormal);
            *surfaceColor += shadeWater(eye, current, n);
            return true;
        }

        if (distWaveBbox(current) >= EPS) {
            return false;
        }

        *p = current + dir * STEPSIZE;
    }
    return true;
}

@vertex
fn vs_main(@location(0) position: vec2<f32>) -> VSOut {
    var out: VSOut;
    out.position = vec4<f32>(position, 0.0, 1.0);
    return out;
}

@fragment
fn fs_main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
    let eye = getCartesian(uniforms.eyeCoordinate);
    let focus = vec3<f32>(0.0, 0.0, 0.0);
    let forward = normalize(focus - eye);
    var right = normalize(getRightVector(uniforms.eyeCoordinate));
    let up = normalize(cross(right, forward));

    let f = 2.0;
    let u = fragCoord.x * 2.0 / uniforms.resolution.x - 1.0;
    let v = fragCoord.y * 2.0 / uniforms.resolution.y - 1.0;

    let ar = uniforms.resolution.x / uniforms.resolution.y;
    right = right * ar;

    let imagePos = eye + right * u + up * v + forward * f;
    let dir = normalize(imagePos - eye);

    var surfaceColor = vec4<f32>(0.0, 0.0, 0.0, 0.0);
    var boxColor = vec4<f32>(0.0, 0.0, 0.0, 0.0);
    let background = vec4<f32>(0.9, 0.9, 0.9, 1.0);
    var wallColor = background;

    var p = eye;
    var surfaceIntersection = eye;

    var floorPos = vec3<f32>(0.0, 0.0, 0.0);
    if (!hitFloor(p, dir, &floorPos)) {
        discard;
    }

    if (!hitBox(&p, dir)) {
        return shadeFloor(eye, floorPos);
    }

    var n = vec3<f32>(0.0, 0.0, 0.0);
    let shootingUp = p.y > eye.y;

    if (p.y < heightAtP(p)) {
        n = getBoxNormal(p);
        surfaceColor = shadeWater(eye, p, n);
    } else {
        if (shootingUp) {
            return background;
        }

        if (hitSurface(dir, eye, &p, &surfaceColor, true)) {
            n = getSurfaceNormal(p);
        } else {
            var floorPos2 = vec3<f32>(0.0, 0.0, 0.0);
            return select(background, shadeFloor(eye, floorPos2), hitFloor(p, dir, &floorPos2));
        }
    }

    var airDir = dir;
    var refractedDir = getRefractedDir(dir, n);
    surfaceIntersection = p;

    p = p + OVERSTEP * refractedDir;
    _ = hitBox(&p, -refractedDir);

    if (p.y > heightAtP(p)) {
        if (!hitSurface(-refractedDir, eye, &p, &surfaceColor, false)) {
            wallColor = shadeWall(eye, p, -getBoxNormal(p));
        } else {
            wallColor = 0.1 * shadeSky(p);
        }
    } else {
        if (p.y > -TANK_HEIGHT) {
            wallColor = shadeWater(eye, p, -getBoxNormal(p));
            var floorPos3 = vec3<f32>(0.0, 0.0, 0.0);
            if (hitFloor(p, airDir, &floorPos3)) {
                wallColor = wallColor + shadeFloor(eye, floorPos3);
            }
        } else {
            wallColor = 0.5 * shadeFloor(eye, p) + vec4<f32>(getCaustics(p), getCaustics(p), getCaustics(p), 1.0);
        }
    }

    let fresnel = getFresnel(n, eye, surfaceIntersection);
    surfaceColor = surfaceColor * 0.3;
    return (1.0 - fresnel) * surfaceColor + (fresnel + 0.3) * wallColor;
}
