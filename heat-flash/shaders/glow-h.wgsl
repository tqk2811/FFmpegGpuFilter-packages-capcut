// Heat Flash, pass 1: keep the parts of the visible clip that rise above the glow threshold, and blur them horizontally with a separate Gaussian width per colour channel.
//
// Widths are measured on a grid GRID texels wide, so the glow scales with the frame.
// Red, green and blue spread over 24, 28.8 and 33.6 grid texels; taps are spaced so at
// most CAP_TAPS land on each side, each nudged by a small random jitter.

const GRID: f32 = 240.0;
const WIDTHS: vec3f = vec3f(24.0, 28.8, 33.6);
const CAP_TAPS: f32 = 30.0;

const START: f32 = 0.4;
const LENGTH: f32 = 1.333333;
const SWAP: f32 = 0.933333;

fn threshold(t: f32) -> f32 {
    if (t >= SWAP) { return 0.0041667; }
    return 0.05 * clamp((t - 0.6) / 0.366667, 0.0, 1.0);
}

// Excess of a channel over the threshold, rescaled to 0..1.
fn over(v: f32, th: f32) -> f32 {
    if (v <= th) { return 0.0; }
    return (v - th) / (1.0 - th);
}

// Highlights of the visible clip at q: the colour keeps its hue, its strength is the summed excess over the threshold.
fn bright(q: vec2f, second_clip: bool, th: f32) -> vec3f {
    var c: vec3f;
    if (second_clip) { c = textureSampleLevel(second, smp, q, 0.0).rgb; }
    else { c = textureSampleLevel(first, smp, q, 0.0).rgb; }
    let k = (over(c.r, th) + over(c.g, th) + over(c.b, th)) / max(c.r + c.g + c.b, 1e-6);
    return c * k;
}

fn jitter(a: f32, b: f32) -> f32 {
    var f = fract(vec2f(a, b) * 13.517);
    f += dot(f, f.yx + 22.541);
    return fract((f.x + f.y) * f.y) - 0.5;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let uv = gpufx_uv(id);
    let t = START + clamp(params.progress, 0.0, 1.0) * LENGTH;
    let sc = t >= SWAP;
    let th = threshold(t);
    let up = vec2f(uv.x, 1.0 - uv.y);
    let texel = vec2f(1.0 / GRID, 0.0);
    let spacing = max(1.0, WIDTHS.z / CAP_TAPS);
    let spread = 2.0 * (WIDTHS / 2.4) * (WIDTHS / 2.4);
    var sum = bright(uv, sc, th);
    var total = vec3f(1.0);
    var d = 1.0;
    for (var i = 0; i < 128; i++) {
        if (d > WIDTHS.z || d > CAP_TAPS * spacing) { break; }
        let w = step(vec3f(d), WIDTHS) * exp(-vec3f(d * d) / spread);
        let fwd = d + spacing * jitter(d + up.x + 0.199, d * up.y);
        let back = d + spacing * jitter(d + up.x + 0.677, d * up.y);
        let a = bright(uv + texel * fwd, sc, th);
        let b = bright(uv - texel * back, sc, th);
        sum += (a + b) * w;
        total += 2.0 * w;
        d += spacing;
    }
    gpufx_write(id, vec4f(sum / total, 1.0));
}
