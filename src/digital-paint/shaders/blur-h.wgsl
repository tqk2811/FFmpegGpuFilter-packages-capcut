// Digital Paint, pass 2: Gaussian blur of both clips' highlights along x in one dispatch (radius 34, sigma 2.25, steps of 1/800 of the short side).

const SPAN: f32 = 2.0;
const RADIUS: f32 = 34.0;
const SIGMA: f32 = 2.25;
const STEPS_PER_SIDE: f32 = 800.0;

fn tap_a(q: vec2f) -> vec4f {
    if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) { return vec4f(0.0); }
    return textureSampleLevel(lit_a, smp, q, 0.0);
}

fn tap_b(q: vec2f) -> vec4f {
    if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) { return vec4f(0.0); }
    return textureSampleLevel(lit_b, smp, q, 0.0);
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let t = clamp(params.progress, 0.0, 1.0) * SPAN;
    let uv = gpufx_uv(id);
    let stride = vec2f(1.0, 0.0) / (globals.size / min(globals.size.x, globals.size.y) * STEPS_PER_SIDE);
    let spread = 2.0 * SIGMA * SIGMA * RADIUS * RADIUS / 100.0;
    // Each clip's glow only runs while its layer is on screen (first until 1.933 s, second from 1.067 s).
    let on_a = t < 1.933333;
    let on_b = t >= 1.066667;
    var sum_a = vec4f(0.0);
    var sum_b = vec4f(0.0);
    if (on_a) { sum_a = tap_a(uv) * 10.0; }
    if (on_b) { sum_b = tap_b(uv) * 10.0; }
    var total = 10.0;
    for (var i = 1; i <= 27; i++) {
        let d = f32(i);
        let w = exp(-d * d / spread) * 10.0;
        if (on_a) { sum_a += (tap_a(uv + stride * d) + tap_a(uv - stride * d)) * w; }
        if (on_b) { sum_b += (tap_b(uv + stride * d) + tap_b(uv - stride * d)) * w; }
        total += 2.0 * w;
    }
    gpufx_write(id, select(vec4f(0.0), sum_a / total, on_a));
    gpufx_write1(id, select(vec4f(0.0), sum_b / total, on_b));
}
