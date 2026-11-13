// Brush Portal, pass 3: Gaussian blur of the highlights along y (radius 50, sigma 2.25, steps of 1/800 of the short side).

const RADIUS: f32 = 50.0;
const SIGMA: f32 = 2.25;
const STEPS_PER_SIDE: f32 = 800.0;
const TAPS: i32 = 40; // 8 * RADIUS / 10

fn tap(q: vec2f) -> vec4f {
    if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) { return vec4f(0.0); }
    return textureSampleLevel(blur_h, smp, q, 0.0);
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    // The rim glow is only read between frame 10 and the cut to the plain incoming clip.
    let t = clamp(params.progress, 0.0, 1.0) * 2.0;
    if (t * 30.0 < 10.0 || t >= 1.9666667) { return; }
    let uv = gpufx_uv(id);
    let stride = vec2f(0.0, 1.0) / (globals.size / min(globals.size.x, globals.size.y) * STEPS_PER_SIDE);
    let spread = 2.0 * SIGMA * SIGMA * RADIUS * RADIUS / 100.0;
    var sum = tap(uv) * 10.0;
    var total = 10.0;
    // The blur is linear, so taps 2k-1 and 2k share one bilinear read placed between them by weight.
    for (var k = 1; k <= TAPS / 2; k++) {
        let d0 = f32(2 * k - 1);
        let d1 = f32(2 * k);
        let w0 = exp(-d0 * d0 / spread) * 10.0;
        let w1 = exp(-d1 * d1 / spread) * 10.0;
        let w = w0 + w1;
        let d = (d0 * w0 + d1 * w1) / w;
        sum += (tap(uv + stride * d) + tap(uv - stride * d)) * w;
        total += 2.0 * w;
    }
    gpufx_write(id, sum / total);
}
