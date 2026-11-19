// Hot Shimmers, pass 3: vertical half of the highlight blur.

const GLOW_GRID: f32 = 240.0;
const GLOW_RADIUS: f32 = 13.333333;


// Scene clock of pass 1; the finishing pass only adds the glow while t is in [0.6, 1.3).
const START: f32 = 0.466667;
const END: f32 = 1.433333;

fn glow_off() -> bool {
    let t = START + clamp(params.progress, 0.0, 1.0) * (END - START);
    return t < 0.6 || t >= 1.3;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    // The glow is unused (its gain is 0) outside its window: skip the blur.
    if (glow_off()) { gpufx_write(id, vec4f(0.0, 0.0, 0.0, 1.0)); return; }
    let uv = gpufx_uv(id);
    // Same pixel pitch as the horizontal pass: the grid keeps the frame's aspect ratio.
    let stride = max(globals.size.x / GLOW_GRID, 1.0) / globals.size.y;
    let spread = 2.0 * pow(GLOW_RADIUS / 2.4, 2.0);
    var sum = textureSampleLevel(glow_h, smp, uv, 0.0).rgb;
    var total = 1.0;
    for (var i = 1; i <= 13; i++) {
        let d = f32(i);
        let w = exp(-d * d / spread);
        let up = clamp(uv + vec2f(0.0, d * stride), vec2f(0.0), vec2f(1.0));
        let down = clamp(uv - vec2f(0.0, d * stride), vec2f(0.0), vec2f(1.0));
        sum += (textureSampleLevel(glow_h, smp, up, 0.0).rgb + textureSampleLevel(glow_h, smp, down, 0.0).rgb) * w;
        total += 2.0 * w;
    }
    gpufx_write(id, vec4f(sum / total, 1.0));
}
