// Angle Swap: horizontal glint streak, level 6 of 6. Each level blurs the previous one
// further (gamma 2.4 light mixing); the reach grows toward the cut.

// 0 -> 1 -> 0 triangle peaking at the cut, with a cubic ease-out.
fn peak(t: f32) -> f32 {
    let tri = select(2.0 - 2.0 * t, 2.0 * t, t < 0.5);
    let r = 1.0 - clamp(tri, 0.0, 1.0);
    return 1.0 - r * r * r;
}

// Tap weights: the Gaussian bell over the radius, normalised so they sum to 1 across both sides.
const RADIUS: f32 = 64.0;
const REACH: f32 = 2.0;

const TAPS: i32 = 63;
const WEIGHT = array<f32, 64>(0.0249356893, 0.0248870343, 0.0247416382, 0.0245011966, 0.0241684988, 0.023747374, 0.0232426181, 0.0226599026, 0.0220056685, 0.0212870085, 0.0205115385, 0.0196872645, 0.0188224458, 0.0179254583, 0.0170046627, 0.016068277, 0.0151242601, 0.0141802047, 0.0132432446, 0.0123199753, 0.0114163904, 0.0105378333, 0.00968896473, 0.00887374535, 0.00809543305, 0.00735659328, 0.00665912158, 0.00600427645, 0.005392721, 0.00482457166, 0.00429945204, 0.00381655032, 0.00337467857, 0.00297233238, 0.00260774948, 0.00227896628, 0.00198387119, 0.001720254, 0.00148585086, 0.00127838422, 0.00109559772, 0.000935285879, 0.000795318657, 0.000673661147, 0.000568388612, 0.000477697284, 0.000399911335, 0.00033348645, 0.000277010486, 0.000229201662, 0.000188904739, 0.000155085602, 0.000126824642, 0.000103309283, 8.38259697e-05, 6.77518818e-05, 5.45465988e-05, 4.37439027e-05, 3.4943863e-05, 2.78053163e-05, 2.20388182e-05, 1.74001223e-05, 1.36842134e-05, 1.07199044e-05);

fn light(q: vec2f) -> vec3f {
    return pow(textureSampleLevel(streak_x4, smp, q, 0.0).rgb, vec3f(2.4));
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
