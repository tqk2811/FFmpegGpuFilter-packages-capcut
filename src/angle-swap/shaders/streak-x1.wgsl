// Angle Swap: horizontal glint streak, level 2 of 6. Each level blurs the previous one
// further (gamma 2.4 light mixing); the reach grows toward the cut.

// 0 -> 1 -> 0 triangle peaking at the cut, with a cubic ease-out.
fn peak(t: f32) -> f32 {
    let tri = select(2.0 - 2.0 * t, 2.0 * t, t < 0.5);
    let r = 1.0 - clamp(tri, 0.0, 1.0);
    return 1.0 - r * r * r;
}

// Tap weights: the Gaussian bell over the radius, normalised so they sum to 1 across both sides.
const RADIUS: f32 = 4.0;
const REACH: f32 = 1.0;

const TAPS: i32 = 3;
const WEIGHT = array<f32, 4>(0.39905028, 0.242036229, 0.0540055826, 0.00443304818);

fn light(q: vec2f) -> vec3f {
    return pow(textureSampleLevel(streak_x0, smp, q, 0.0).rgb, vec3f(2.4));
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let uv = gpufx_uv(id);
    let t = clamp(params.progress, 0.0, 1.0);
    let spread = 0.18 * peak(t);
    let aspect = globals.size / min(globals.size.x, globals.size.y);
    var unit = vec2f(0.0);
    unit.x = REACH * spread / (aspect.x * 360.0);
    var sum = light(uv) * WEIGHT[0];
    for (var i = 1; i <= TAPS; i++) {
        let o = unit * f32(i);
        sum += (light(uv + o) + light(uv - o)) * WEIGHT[i];
    }
    gpufx_write(id, vec4f(pow(sum, vec3f(1.0 / 2.4)), 1.0));
}
