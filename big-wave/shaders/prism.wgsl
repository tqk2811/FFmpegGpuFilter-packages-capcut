// Big wave, step 4: prism split, strongest at the clip switch.

const TIMELINE: f32 = 0.8333333;
const SWITCH_AT: f32 = 0.366667;
const TAU: f32 = 6.2831853;

fn timeline_now() -> f32 { return clamp(params.progress, 0.0, 1.0) * TIMELINE; }

// CSS-like cubic-bezier easing through (0,0) (x1,y1) (x2,y2) (1,1), solved for x by bisection.
fn bezier_axis(a: f32, b: f32, s: f32) -> f32 {
    let r = 1.0 - s;
    return 3.0 * a * r * r * s + 3.0 * b * r * s * s + s * s * s;
}

fn ease(x1: f32, y1: f32, x2: f32, y2: f32, u: f32) -> f32 {
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 22; i++) {
        let mid = 0.5 * (lo + hi);
        if (bezier_axis(x1, x2, mid) > u) { hi = mid; } else { lo = mid; }
    }
    return bezier_axis(y1, y2, 0.5 * (lo + hi));
}

// One keyframe segment: keeps `cur` before `t0`, eases from v0 to v1 inside, holds v1 after.
fn key(cur: f32, t: f32, t0: f32, t1: f32, v0: f32, v1: f32, e: vec4f) -> f32 {
    if (t < t0) { return cur; }
    if (t >= t1) { return v1; }
    return mix(v0, v1, ease(e.x, e.y, e.z, e.w, (t - t0) / (t1 - t0)));
}

const LINEAR = vec4f(0.1666667, 0.1666667, 0.8333333, 0.8333333);

fn mirror01(q: vec2f) -> vec2f {
    return abs(((q - 1.0) % 2.0 + 2.0) % 2.0 - 1.0);
}

// ---- Prism: a zoom blur from 1.04x to 0.96x whose taps are tinted red -> blue -> green, splitting RGB apart ----
// (no twist and no falloff here, so the taps lie on one ray and only the zoom moves them)

const SCALE_A: f32 = 1.04;
const SCALE_B: f32 = 0.96;

fn ramp(x: f32) -> vec3f {
    let wa = clamp(1.0 - abs(x) / 0.5, 0.0, 1.0);
    let wm = clamp(1.0 - abs(x - 0.5) / 0.5, 0.0, 1.0);
    let wb = clamp(1.0 - abs(x - 1.0) / 0.5, 0.0, 1.0);
    return vec3f(wa, wb, wm);
}

fn prism(tex: texture_2d<f32>, uv: vec2f, amount: f32) -> vec4f {
    let centre = vec2f(0.5);
    let taps = floor(max(80.0 * abs(SCALE_B - SCALE_A) * sqrt(length(uv - centre)) * 4.0, 6.0));
    let d = uv - centre;
    let qa = d / mix(1.0, SCALE_A, amount) + centre;
    let qb = d / mix(1.0, SCALE_B, amount) + centre;
    let expo = 1.0 + (SCALE_A - SCALE_B) * 2.0;
    let inv_taps = 1.0 / taps;
    var lit = vec3f(0.0);
    var norm = vec3f(0.0);
    for (var k = 0.0; k <= taps; k += 1.0) {
        let f = k * inv_taps;
        let tint = ramp(1.0 - f) * pow(clamp(1.0 - f, 0.001, 1.0), expo);
        let c = textureSampleLevel(tex, smp, mirror01(mix(qa, qb, f)), 0.0).rgb;
        lit += c * tint;
        norm += tint;
    }
    return vec4f(lit / norm, 1.0);
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let t = timeline_now();
    var amount = key(0.0, t, 0.0, 0.366667, 0.0, 62.559743, vec4f(0.42, 0.0, 0.999, 1.0));
    amount = key(amount, t, 0.366667, 0.8, 62.559743, 0.0, vec4f(0.001, 0.0, 0.58, 1.0));
    let uv = gpufx_uv(id);
    var c = textureSampleLevel(waved, smp, uv, 0.0);
    if (amount > 0.0) {
        c = prism(waved, uv, amount / 100.0);
    }
    gpufx_write(id, vec4f(c.rgb, 1.0));
}
