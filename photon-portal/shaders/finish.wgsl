// Photon Portal, pass 3: blur the highlights vertically and add the glow on top while it swells and fades.

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

const TAP_GRID: f32 = 800.0;
const TAPS: i32 = 40;
const SPREAD: f32 = 253.125;

// Vertical half of the highlight blur, read where it is used. The blur is linear, so taps 2k-1
// and 2k share one bilinear read placed between them by weight.
fn glow_at(uv: vec2f) -> vec3f {
    let stride = min(globals.size.x, globals.size.y) / TAP_GRID / globals.size.y;
    var sum = textureSampleLevel(glow_h, smp, uv, 0.0).rgb * 10.0;
    var total = 10.0;
    for (var k = 1; k <= TAPS / 2; k++) {
        let d0 = f32(2 * k - 1);
        let d1 = f32(2 * k);
        let w0 = exp(-d0 * d0 / SPREAD) * 10.0;
        let w1 = exp(-d1 * d1 / SPREAD) * 10.0;
        let w = w0 + w1;
        let d = (d0 * w0 + d1 * w1) / w;
        let dn = uv.y + d * stride;
        let up = uv.y - d * stride;
        if (dn <= 1.0) { sum += textureSampleLevel(glow_h, smp, vec2f(uv.x, dn), 0.0).rgb * w; }
        if (up >= 0.0) { sum += textureSampleLevel(glow_h, smp, vec2f(uv.x, up), 0.0).rgb * w; }
        total += 2.0 * w;
    }
    return sum / total;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let uv = gpufx_uv(id);
    // Exact clips at the ends of the transition.
    if (params.progress <= 0.0) { gpufx_write(id, vec4f(textureSampleLevel(first, smp, uv, 0.0).rgb, 1.0)); return; }
    if (params.progress >= 1.0) { gpufx_write(id, vec4f(textureSampleLevel(second, smp, uv, 0.0).rgb, 1.0)); return; }
    let t = params.progress * SCENE;
    let base = textureSampleLevel(scene, smp, uv, 0.0).rgb;
    let gain = glow_gain(t);
    var halo = vec3f(0.0);
    if (gain > 0.0) { halo = glow_at(uv) * gain; }
    gpufx_write(id, vec4f(clamp(base + halo, vec3f(0.0), vec3f(1.0)), 1.0));
}
