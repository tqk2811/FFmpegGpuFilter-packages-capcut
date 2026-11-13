// Negative Glitch, pass 1: grade (clip of the current half faded towards its negative, exposure pushed), shake and zoom the frame (mirrored edges), then smear it sideways like a weak analogue signal.

const SPAN: f32 = 2.0;
const PI: f32 = 3.14159265;
const DESIGN: f32 = 1080.0; // shake amplitudes are in pixels of a 1080 px short side
const STEP: f32 = 1.0 / 720.0; // smear taps, in units of the short side

fn ramp(t: f32, t0: f32, t1: f32, v0: f32, v1: f32) -> f32 {
    let u = clamp((t - t0) / (t1 - t0), 0.0, 1.0);
    return mix(v0, v1, u * u * (3.0 - 2.0 * u));
}

fn speed_gain(t: f32) -> f32 {
    if (t < 1.00166) { return ramp(t, 0.952507, 1.00166, 0.1, 3.5); }
    return ramp(t, 1.00166, 1.050846, 3.5, 0.1);
}

fn zoom_out(t: f32) -> f32 {
    if (t < 1.05599) { return ramp(t, 0.947852, 1.05599, 1.0, 1.3); }
    return ramp(t, 1.05599, 1.16416, 1.3, 1.0);
}

// Vertical camera wobble in design pixels: one steady sine plus a three-tone wander.
fn wobble(clock: f32, gain: f32) -> f32 {
    let steady = sin(PI * clock * gain * 0.5) * 80.0;
    let a = PI * clock * gain * 6.7;
    let wander = sin(a) * 0.25 + cos(a * 1.5) * 0.16 + sin(a * 2.5) * 0.09;
    return steady + wander * 192.0;
}

fn invert_amount(t: f32) -> f32 {
    if (t < 1.1) { return ramp(t, 0.780176, 0.952507, 0.0, 1.0); }
    return ramp(t, 1.1, 1.272298, 1.0, 0.0);
}

fn stops(t: f32) -> f32 {
    if (t < 1.00166) { return ramp(t, 0.903255, 1.00166, 0.0, 4.2); }
    return ramp(t, 1.00166, 1.1, 4.2, 0.0);
}

// Grade settings of the current time, shared by every tap.
struct Grade { use_second: bool, invert: f32, gain: f32 }

fn grade(c0: vec3f, g: Grade) -> vec3f {
    let c = mix(c0, vec3f(1.0) - c0, g.invert);
    // Exposure in linear light (gamma 2.2), then back.
    let lin = pow(max(c, vec3f(0.0)), vec3f(2.2)) * g.gain;
    return clamp(pow(lin, vec3f(1.0 / 2.2)), vec3f(0.0), vec3f(1.0));
}

fn mirror(x: vec2f) -> vec2f {
    return abs((x + 1.0) - 2.0 * floor((x + 1.0) * 0.5) - 1.0);
}

fn texel(p: vec2i, g: Grade) -> vec3f {
    if (g.use_second) { return textureLoad(second, p, 0).rgb; }
    return textureLoad(first, p, 0).rgb;
}

// Graded clip at s: the grade is applied to each texel before the bilinear blend, as a graded texture would be.
fn shaken(uv: vec2f, origin: vec2f, scale: f32, g: Grade) -> vec3f {
    let s = mirror((uv - 0.5) * scale + 0.5 + origin);
    let size = vec2i(globals.size);
    let x = s * globals.size - 0.5;
    let i = vec2i(floor(x));
    let f = x - floor(x);
    let lo = clamp(i, vec2i(0), size - 1);
    let hi = clamp(i + 1, vec2i(0), size - 1);
    let top = mix(grade(texel(lo, g), g), grade(texel(vec2i(hi.x, lo.y), g), g), f.x);
    let bot = mix(grade(texel(vec2i(lo.x, hi.y), g), g), grade(texel(hi, g), g), f.x);
    return mix(top, bot, f.y);
}

fn to_ycc(c: vec3f) -> vec3f {
    let y = dot(c, vec3f(0.299, 0.587, 0.114));
    return vec3f(y, (c.b - y) * 0.565, (c.r - y) * 0.713);
}

fn from_ycc(v: vec3f) -> vec3f {
    return vec3f(v.x + 1.403 * v.z, v.x - 0.344 * v.y - 0.714 * v.z, v.x + 1.77 * v.y);
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let uv = gpufx_uv(id);
    let t = clamp(params.progress, 0.0, 1.0) * SPAN;
    let short_side = min(globals.size.x, globals.size.y);
    let frame = globals.size / short_side; // frame size in short-side units
    let clock = params.progress * params.duration;
    let scale = zoom_out(t);
    let origin = vec2f(0.0, -wobble(clock, speed_gain(t)) / DESIGN) * scale / frame;
    let dx = vec2f(STEP / frame.x, 0.0);
    let g = Grade(t >= 1.0, invert_amount(t), exp2(stops(t)));

    let here = shaken(uv, origin, scale, g);
    var sum = here;
    for (var i = 1; i <= 8; i++) { sum += shaken(uv - dx * f32(i), origin, scale, g); }
    let sharp = clamp(here + (here - sum / 9.0) * 0.6, vec3f(0.0), vec3f(1.0));
    var ycc = to_ycc(sharp);
    let trail = to_ycc(shaken(uv - dx * 8.0, origin, scale, g));
    ycc = vec3f(ycc.x, mix(ycc.yz, trail.yz, vec2f(0.6)));
    let soft = clamp(from_ycc(ycc), vec3f(0.0), vec3f(1.0));
    gpufx_write(id, vec4f(mix(here, soft, 0.8), 1.0));
}
