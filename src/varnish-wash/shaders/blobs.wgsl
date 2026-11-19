// Varnish Wash, pass 1: a burst of metaballs sprays out of one point and grows into a liquid mask.
//
// Every blob is born at the emitter, flies off on a random heading and swells; their soft union
// is written as a height field packed into three 8-bit channels (alpha = coverage).

// Length of the animation in seconds; `progress` maps onto it.
const SPAN: f32 = 1.966667;
// Extra clock offset added on top of the scene time.
const CLOCK_LEAD: f32 = 0.0;
// Emitter, in the effect's bottom-up coordinate space.
const EMITTER: vec2f = vec2f(0.605556, 0.452778);
const SPREAD: vec2f = vec2f(1.0, 1.0);
const RATE: f32 = 99.0;
const LIFE: f32 = 1.0;
const EMITTER_LIFE: f32 = 600.0;
const SIZE_END: f32 = 0.3;
const SIZE_JITTER: f32 = 1.0;
const SPEED: f32 = 1.0;
const DRAG: f32 = 2.0;
const SIDEWAYS: f32 = 1.0;
const HEIGHT_CURVE: f32 = 0.5;
const MAX_BLOBS: i32 = 200;

// Cubic Bezier easing through (0,0), (x1,y1), (x2,y2), (1,1), solved for x by Newton steps.
fn bezier_ease(x: f32, x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
    var s = x;
    for (var i = 0; i < 8; i++) {
        let inv = 1.0 - s;
        let bx = 3.0 * inv * inv * s * x1 + 3.0 * inv * s * s * x2 + s * s * s;
        let dx = 3.0 * inv * inv * x1 + 6.0 * inv * s * (x2 - x1) + 3.0 * s * s * (1.0 - x2);
        if (abs(dx) < 1e-5) { break; }
        s = clamp(s - (bx - x) / dx, 0.0, 1.0);
    }
    let inv = 1.0 - s;
    return 3.0 * inv * inv * s * y1 + 3.0 * inv * s * s * y2 + s * s * s;
}

fn keyed(t: f32, t0: f32, t1: f32, a: f32, b: f32) -> f32 {
    let x = clamp((t - t0) / (t1 - t0), 0.0, 1.0);
    return mix(a, b, bezier_ease(x, 0.33333333, 0.0, 0.66666667, 1.0));
}

// Two-input hash in [0, 1).
fn hash2(a: f32, b: f32) -> f32 {
    var f = fract(vec2f(a, b) * 13.517);
    f += dot(f, f.yx + 22.541);
    return fract((f.x + f.y) * f.y);
}

// Draws the next random number and advances the seed.
fn draw(seed: ptr<function, f32>) -> f32 {
    let r = hash2(*seed + 0.233, 7.19);
    *seed = hash2(*seed + 0.541, r);
    return r;
}

// The four random draws of blob `i` (origin xy, heading zw); they only depend on the frame.
fn burst_draws(i: i32, seed: ptr<function, f32>) -> vec4f {
    *seed = hash2(f32(i) + 1.513, hash2(*seed, 0.723));
    let ox = draw(seed);
    let oy = draw(seed);
    let rx = draw(seed);
    let ry = draw(seed);
    return vec4f(ox, oy, rx, ry);
}

// Position offset (xy) and velocity (zw) of a blob from its draws at life fraction `life_in`.
fn burst(r: vec4f, life_in: f32, aspect: f32) -> vec4f {
    let life = life_in / max(DRAG, 0.1);
    let vy = (r.w - 0.5) * SPEED * aspect;
    let vx = (r.z - 0.5) * SPEED * SIDEWAYS * aspect;
    return vec4f(((r.x - 0.5) * SPREAD.x + vx * life) * aspect, (r.y - 0.5) * SPREAD.y + vy * life, vx, vy);
}

// Squared distance to an ellipse stretched along its direction of travel, minus the radius squared.
fn stretched_blob(p: vec2f, frame: vec2f, centre: vec2f, radius: f32, vel: vec2f) -> f32 {
    let speed = length(vel);
    let dir = vel / max(speed, 1e-8);
    let d = (p - centre) * frame;
    var q = vec2f(dir.x * d.x + dir.y * d.y, -dir.y * d.x + dir.x * d.y);
    q.x *= 1.0 / (1.0 + speed);
    return dot(q, q) - radius * radius;
}

fn soft_min(a: f32, b: f32, k: f32) -> f32 {
    if (k <= 0.0) { return min(a, b); }
    let h = clamp((b - a) / k + 0.5, 0.0, 1.0);
    return mix(b, a, h) - h * (1.0 - h) * k * 0.5;
}

fn pack3(v_in: f32) -> vec3f {
    var v = v_in * 255.0;
    let x = floor(v) / 255.0;
    v = fract(v) * 255.0;
    let y = floor(v) / 255.0;
    v = fract(v) * 255.0;
    return vec3f(x, y, floor(v) / 255.0);
}

// Per-frame blob table, built once per workgroup: random draws (origin.xy, heading.zw), (radius, life, -, live).
var<workgroup> blob_a: array<vec4f, MAX_BLOBS>;
var<workgroup> blob_b: array<vec4f, MAX_BLOBS>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u, @builtin(local_invocation_index) lid: u32) {
    let scene = clamp(params.progress, 0.0, 1.0) * SPAN;
    let clock = scene + CLOCK_LEAD;
    let pull = keyed(scene, 0.366667, 1.733333, 0.0, 1.53);
    let size_start = keyed(scene, 0.366667, 1.733333, 0.51, 5.0);

    let aspect = globals.size.y / globals.size.x;
    let frame = globals.size / max(globals.size.x, globals.size.y);
    let life_span = max(LIFE, 0.001);
    let count = i32(min(min(clock, life_span) * RATE, f32(MAX_BLOBS)));
    let last = min(count, MAX_BLOBS - 1);

    // Each thread of the group fills a few table rows; blob parameters only depend on the frame.
    for (var i = i32(lid) + 1; i <= last; i += 64) {
        var live = 0.0;
        var a = vec4f(0.0);
        var r2 = 0.0;
        var sh = 0.0;
        let age = clock / life_span - f32(i) / RATE;
        if (!(age < 0.0 || age > floor(EMITTER_LIFE / life_span))) {
            var seed = floor(age) * 0.353 + f32(i);
            let life = fract(age);
            let scale = 1.0 + (draw(&seed) - 0.5) * SIZE_JITTER;
            let born = size_start * scale;
            let dies = SIZE_END * scale;
            let shape = 0.5 + draw(&seed);
            var radius: f32;
            if (life < 0.1) {
                radius = mix(0.0, born, pow(life * 10.0, shape));
            } else if (life < 0.9) {
                radius = mix(born, dies, pow((life - 0.1) / 0.8, shape));
            } else {
                radius = mix(dies, 0.0, pow((life - 0.9) * 10.0, shape));
            }
            radius *= pull * 0.1;
            a = burst_draws(i, &seed);
            sh = life;
            r2 = radius;
            live = 1.0;
        }
        blob_a[i] = a;
        blob_b[i] = vec4f(r2, sh, 0.0, live);
    }
    workgroupBarrier();

    if (!gpufx_in_bounds(id)) { return; }
    let uv = gpufx_uv(id);
    let p = vec2f(uv.x, 1.0 - uv.y);

    var field = 0.0;
    if (count > 0) {
        field = 10000.0;
        let k = pull * 3.0;
        for (var i = 1; i <= last; i++) {
            let b = blob_b[i];
            if (b.w == 0.0) { continue; }
            let a = blob_a[i];
            let radius = b.x;
            let m = burst(a, b.y, aspect);
            let d = stretched_blob(p, frame, EMITTER - m.xy, radius, m.zw * 0.5) / (radius * radius + 1e-4);
            field = soft_min(field, d, k);
        }
    }
    let height = pow(clamp(-field * 0.2, 0.0, 1.0), HEIGHT_CURVE);
    gpufx_write(id, vec4f(pack3(height), smoothstep(0.0, 0.1, height)));
}
