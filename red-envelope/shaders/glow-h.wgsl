// Red Envelope, glow pass 1: pick out the highlights of the second clip and blur them horizontally, out to 0.8 x radius steps.

// The animation runs over two seconds of scene time.
const SPAN: f32 = 2.0;

fn clock() -> f32 { return clamp(params.progress, 0.0, 1.0) * SPAN; }

// Cubic Bezier easing through (0,0), (x1,y1), (x2,y2), (1,1), solved for x by bisection.
fn bezier_ease(x: f32, c: vec4f) -> f32 {
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 20; i++) {
        let s = 0.5 * (lo + hi);
        let inv = 1.0 - s;
        let bx = 3.0 * inv * inv * s * c.x + 3.0 * inv * s * s * c.z + s * s * s;
        if (bx > x) { hi = s; } else { lo = s; }
    }
    let s = 0.5 * (lo + hi);
    let inv = 1.0 - s;
    return 3.0 * inv * inv * s * c.y + 3.0 * inv * s * s * c.w + s * s * s;
}

const SOFT: vec4f = vec4f(0.166667, 0.166667, 0.833333, 0.833333);

// The glow pulses twice: off at the keys 1.0 and 1.466667 / 1.966667, full at 1.3 and 1.8.
// Returns 0 (glow off) .. 1 (glow full) along that pulse train.
fn pulse(t: f32) -> f32 {
    let keys = array<f32, 6>(1.0, 1.166667, 1.3, 1.466667, 1.8, 1.966667);
    let vals = array<f32, 6>(0.0, 0.0, 1.0, 0.0, 1.0, 0.0);
    if (t < keys[0] || t >= keys[5]) { return 0.0; }
    var k = 0;
    for (var i = 0; i < 5; i++) { if (t >= keys[i]) { k = i; } }
    let x = clamp((t - keys[k]) / (keys[k + 1] - keys[k]), 0.0, 1.0);
    return mix(vals[k], vals[k + 1], bezier_ease(x, SOFT));
}

fn glow_radius(t: f32) -> f32 { return 100.0 * pulse(t); }

// Blur width of each glow sigma unit; one blur step is 1/800 of the short side.
const SIGMA: f32 = 2.25;
const STEPS_PER_SIDE: f32 = 800.0;

fn glow_threshold(t: f32) -> f32 { return 1.0 - pulse(t); }

fn highlight(p: vec2i, thr: f32) -> vec4f {
    let c = textureLoad(second, p, 0);
    let knee = clamp(thr, 0.01, 1.0);
    let lit = smoothstep(vec3f(knee - 0.075 * thr), vec3f(knee + 0.115), c.rgb);
    return vec4f(pow(lit, vec3f(1.0 / 2.2)), c.a);
}

// Highlight of the second clip at q (gamma encoded), nothing off the frame. The taps move along the row only, so the
// highlight of the two texels around q is blended in x, as a highlight texture sampled bilinearly would be.
fn tap(q: vec2f, thr: f32) -> vec4f {
    if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) { return vec4f(0.0); }
    let size = vec2i(globals.size);
    let x = q.x * globals.size.x - 0.5;
    let i = i32(floor(x));
    let y = clamp(i32(q.y * globals.size.y), 0, size.y - 1);
    let a = highlight(vec2i(clamp(i, 0, size.x - 1), y), thr);
    let b = highlight(vec2i(clamp(i + 1, 0, size.x - 1), y), thr);
    return mix(a, b, x - floor(x));
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let uv = gpufx_uv(id);
    let r = glow_radius(clock());
    let thr = glow_threshold(clock());
    let stride = vec2f(1.0, 0.0) / (globals.size / min(globals.size.x, globals.size.y) * STEPS_PER_SIDE);
    var sum = tap(uv, thr) * 10.0;
    var total = 10.0;
    let spread = 2.0 * SIGMA * SIGMA * r * r / 100.0;
    for (var i = 1; i <= 80; i++) {
        let d = f32(i);
        if (d > 0.8 * r) { break; }
        let w = exp(-d * d / spread) * 10.0;
        sum += (tap(uv + stride * d, thr) + tap(uv - stride * d, thr)) * w;
        total += 2.0 * w;
    }
    gpufx_write(id, sum / total);
}
