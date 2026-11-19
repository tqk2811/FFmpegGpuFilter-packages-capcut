// Digital Paint, pass 1: soft-threshold highlights of both clips in one dispatch; each threshold pulses 0.8 / 0.4 then settles at 1.

const SPAN: f32 = 2.0; // scene seconds covered by progress 0..1

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

fn threshold_a(t: f32) -> f32 {
    let keys = array<f32, 6>(0.0, 0.159993, 0.319987, 0.480013, 0.6, 0.733333);
    let vals = array<f32, 6>(0.8, 0.4, 0.8, 0.4, 0.8, 1.0);
    if (t <= keys[0]) { return vals[0]; }
    if (t >= keys[5]) { return vals[5]; }
    var k = 0;
    for (var i = 0; i < 5; i++) { if (t >= keys[i]) { k = i; } }
    var curve = vec4f(0.33333333, 0.0, 0.66666667, 1.0);
    if (k == 4) { curve = vec4f(0.166666667, 0.0, 0.833333333, 1.0); }
    let x = clamp((t - keys[k]) / (keys[k + 1] - keys[k]), 0.0, 1.0);
    return mix(vals[k], vals[k + 1], bezier_ease(x, curve));
}

fn threshold_b(t: f32) -> f32 {
    let keys = array<f32, 6>(1.1, 1.259993, 1.419987, 1.580013, 1.7, 2.066667);
    let vals = array<f32, 6>(0.8, 0.4, 0.8, 0.4, 0.8, 1.0);
    if (t <= keys[0]) { return vals[0]; }
    if (t >= keys[5]) { return vals[5]; }
    var k = 0;
    for (var i = 0; i < 5; i++) { if (t >= keys[i]) { k = i; } }
    var curve = vec4f(0.33333333, 0.0, 0.66666667, 1.0);
    if (k == 4) { curve = vec4f(0.166666667, 0.0, 0.833333333, 1.0); }
    let x = clamp((t - keys[k]) / (keys[k + 1] - keys[k]), 0.0, 1.0);
    return mix(vals[k], vals[k + 1], bezier_ease(x, curve));
}

fn highlights(src: vec4f, th: f32) -> vec4f {
    let knee = clamp(th, 0.01, 1.0);
    let lit = smoothstep(vec3f(knee - 0.075 * th), vec3f(knee + 0.115), src.rgb);
    return vec4f(pow(lit, vec3f(0.45454544)), src.a);
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let t = clamp(params.progress, 0.0, 1.0) * SPAN;
    let uv = gpufx_uv(id);
    // The first clip's layer ends at 1.933 s of scene time.
    var lit_first = vec4f(0.0);
    if (t < 1.933333) { lit_first = highlights(textureSampleLevel(first, smp, uv, 0.0), threshold_a(t)); }
    gpufx_write(id, lit_first);
    // The glowing second clip's layer starts at 1.067 s of scene time.
    var lit_second = vec4f(0.0);
    if (t >= 1.066667) { lit_second = highlights(textureSampleLevel(second, smp, uv, 0.0), threshold_b(t)); }
    gpufx_write1(id, lit_second);
}
