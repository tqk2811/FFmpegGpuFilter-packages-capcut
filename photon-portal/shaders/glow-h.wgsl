// Photon Portal, pass 2: keep the bright parts of the scene and blur them horizontally.
//
// One blur tap spans short_side / 800 pixels; 40 taps per side, Gaussian weights with
// sigma 2.25 at radius 50 (2 * 2.25^2 * 50^2 / 100 = 253.125).

const TAP_GRID: f32 = 800.0;
const TAPS: i32 = 40;
const SPREAD: f32 = 253.125;

fn highlights(q: vec2f) -> vec3f {
    let c = textureSampleLevel(scene, smp, q, 0.0).rgb;
    let k = smoothstep(vec3f(0.555), vec3f(0.715), c);
    return pow(k, vec3f(0.4545454));
}

// The finish pass scales the glow by glow_gain; outside its window the blur is skipped.
const SCENE: f32 = 1.033333;
const SOFT: vec4f = vec4f(0.1666667, 0.1666667, 0.8333333, 0.8333333);

fn bezier_y(x: f32, k: vec4f) -> f32 {
    var lo = 0.0;
    var hi = 1.0;
    for (var n = 0; n < 16; n++) {
        let s = (lo + hi) * 0.5;
        let r = 1.0 - s;
        if (3.0 * r * r * s * k.x + 3.0 * r * s * s * k.z + s * s * s > x) { hi = s; } else { lo = s; }
    }
    let s = (lo + hi) * 0.5;
    let r = 1.0 - s;
    return 3.0 * r * r * s * k.y + 3.0 * r * s * s * k.w + s * s * s;
}

fn glow_gain(t: f32) -> f32 {
    if (t <= 0.133333 || t >= 0.433333) { return 0.0; }
    if (t < 0.266667) { return bezier_y((t - 0.133333) / 0.133334, SOFT); }
    return 1.0 - bezier_y((t - 0.266667) / 0.166666, SOFT);
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let uv = gpufx_uv(id);
    if (glow_gain(params.progress * SCENE) == 0.0) { gpufx_write(id, vec4f(0.0, 0.0, 0.0, 1.0)); return; }
    let stride = min(globals.size.x, globals.size.y) / TAP_GRID / globals.size.x;
    var sum = highlights(uv) * 10.0;
    var total = 10.0;
    for (var i = 1; i <= TAPS; i++) {
        let d = f32(i);
        let w = exp(-d * d / SPREAD) * 10.0;
        let rx = uv.x + d * stride;
        let lx = uv.x - d * stride;
        if (rx <= 1.0) { sum += highlights(vec2f(rx, uv.y)) * w; }
        if (lx >= 0.0) { sum += highlights(vec2f(lx, uv.y)) * w; }
        total += 2.0 * w;
    }
    gpufx_write(id, vec4f(sum / total, 1.0));
}
