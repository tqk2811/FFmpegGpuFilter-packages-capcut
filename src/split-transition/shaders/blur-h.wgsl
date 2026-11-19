// Picks out the highlights of the second clip and runs the horizontal half of the gaussian blur that spreads them into a glow.

// Glow keyframes on the transition clock: the glow pulses three times, each pulse a
// one-frame flare followed by a fade (knots in progress units, linear in between).
var<private> GLOW_T: array<f32, 7> = array<f32, 7>(0.1, 0.133333, 0.233333, 0.266667, 0.5, 0.533333, 1.0);
var<private> GLOW_THRESHOLD: array<f32, 7> = array<f32, 7>(1.0, 0.1, 1.0, 0.1, 1.0, 0.1, 1.0);
var<private> GLOW_RADIUS: array<f32, 7> = array<f32, 7>(0.0, 100.0, 0.0, 100.0, 0.0, 100.0, 0.0);

fn glow_key(values: ptr<private, array<f32, 7>>, t: f32) -> f32 {
    if (t <= GLOW_T[0]) { return (*values)[0]; }
    for (var i = 1; i < 7; i++) {
        if (t <= GLOW_T[i]) {
            let k = (t - GLOW_T[i - 1]) / (GLOW_T[i] - GLOW_T[i - 1]);
            return mix((*values)[i - 1], (*values)[i], k);
        }
    }
    return (*values)[6];
}

// Width of the gaussian relative to the radius.
const SIGMA: f32 = 4.0;

// Taps that fall outside the frame add nothing but still count in the weight sum,
// so the glow fades toward the borders.
fn highlight(p: vec2i, level: f32) -> vec4f {
    let c = textureLoad(second, p, 0);
    let lo = clamp(level, 0.01, 1.0);
    let bright = smoothstep(vec3f(lo - 0.075 * level), vec3f(lo + 0.115), c.rgb);
    return vec4f(pow(bright, vec3f(1.0 / 2.2)), c.a);
}

// Highlight of the second clip at uv (gamma encoded), nothing past the left and right edges. The taps move along the
// row only, so the highlight of the two texels around uv is blended in x, as a highlight texture sampled bilinearly would be.
fn tap(uv: vec2f, level: f32) -> vec4f {
    let inside = step(0.0, uv.x) * step(uv.x, 1.0);
    let size = vec2i(globals.size);
    let x = uv.x * globals.size.x - 0.5;
    let i = i32(floor(x));
    let y = clamp(i32(uv.y * globals.size.y), 0, size.y - 1);
    let a = highlight(vec2i(clamp(i, 0, size.x - 1), y), level);
    let b = highlight(vec2i(clamp(i + 1, 0, size.x - 1), y), level);
    return mix(a, b, x - floor(x)) * inside;
}

fn clock() -> f32 {
    return clamp(params.progress, 0.0, 1.0);
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let uv = gpufx_uv(id);
    let radius = glow_key(&GLOW_RADIUS, clock());
    let level = glow_key(&GLOW_THRESHOLD, clock());
    // One tap step is 1/800 of the shorter side.
    let step_uv = vec2f(1.0, 0.0) / (globals.size / min(globals.size.x, globals.size.y) * 800.0);
    var sum = tap(uv, level) * 10.0;
    var total = 10.0;
    let spread = 2.0 * SIGMA * SIGMA * radius * radius / 100.0;
    let count = i32(floor(0.8 * radius));
    for (var i = 1; i <= count; i++) {
        let fi = f32(i);
        let w = exp(-fi * fi / spread) * 10.0;
        sum += (tap(uv + step_uv * fi, level) + tap(uv - step_uv * fi, level)) * w;
        total += 2.0 * w;
    }
    gpufx_write(id, sum / total);
}
