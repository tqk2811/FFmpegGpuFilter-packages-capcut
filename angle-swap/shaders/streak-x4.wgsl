// Angle Swap: horizontal glint streak, level 5 of 6. Each level blurs the previous one
// further (gamma 2.4 light mixing); the reach grows toward the cut.

// 0 -> 1 -> 0 triangle peaking at the cut, with a cubic ease-out.
fn peak(t: f32) -> f32 {
    let tri = select(2.0 - 2.0 * t, 2.0 * t, t < 0.5);
    let r = 1.0 - clamp(tri, 0.0, 1.0);
    return 1.0 - r * r * r;
}

// Tap weights: the Gaussian bell over the radius, normalised so they sum to 1 across both sides.
const RADIUS: f32 = 32.0;
const REACH: f32 = 2.0;

const TAPS: i32 = 31;
const WEIGHT = array<f32, 32>(0.0498718476, 0.0494837418, 0.0483374522, 0.0464856735, 0.0440117511, 0.0410234629, 0.0376452456, 0.0340096452, 0.0302488047, 0.0264867383, 0.0228329957, 0.0193781117, 0.0161910184, 0.0133183684, 0.0107855435, 0.00859898496, 0.00674942063, 0.00521554802, 0.0039677797, 0.00297172968, 0.00219121606, 0.00159065228, 0.00113678792, 0.000799830194, 0.000554026183, 0.000377813031, 0.00025365167, 0.000167653516, 0.000109094224, 6.98883834e-05, 4.40780509e-05, 2.73686842e-05);

fn light(q: vec2f) -> vec3f {
    return pow(textureSampleLevel(streak_x3, smp, q, 0.0).rgb, vec3f(2.4));
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
