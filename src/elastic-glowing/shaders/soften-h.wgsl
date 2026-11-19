// Horizontal half of the soft blur that peaks while the clips swap.

// Blur strength over progress (45 even steps).
const SOFTEN = array<f32, 45>(
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 14.5, 29.0, 27.754, 24.469, 19.824, 14.5, 9.1758,
    4.5312, 1.2461, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0,
);

// Blur strength to gaussian sigma, in pixels of a 1080-pixel-high frame.
const SIGMA_PER_UNIT: f32 = 0.5;

fn curve(t: array<f32, 45>, p: f32) -> f32 {
    var a = t;
    let k = clamp(p, 0.0, 1.0) * 44.0;
    let i = u32(floor(k));
    return mix(a[i], a[min(i + 1u, 44u)], k - floor(k));
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let size = vec2i(textureDimensions(streaks));
    let p = vec2i(id.xy);
    let sigma = curve(SOFTEN, params.progress) * SIGMA_PER_UNIT * globals.size.y / 1080.0;
    var c = textureLoad(streaks, p, 0).rgb;
    if (sigma > 0.3) {
        let r = i32(min(ceil(sigma * 3.0), 96.0));
        // Pairs of neighbouring taps share one bilinear sample placed between them by weight.
        let texel = 1.0 / vec2f(textureDimensions(streaks));
        let centre = (vec2f(p) + 0.5) * texel;
        let k = -0.5 / (sigma * sigma);
        var sum = vec3f(0.0);
        var wsum = 0.0;
        var i = -r;
        for (; i < r; i += 2) {
            let w0 = exp(f32(i * i) * k);
            let w1 = exp(f32((i + 1) * (i + 1)) * k);
            let o = (f32(i) + w1 / (w0 + w1)) * texel.x;
            sum += (w0 + w1) * textureSampleLevel(streaks, smp, centre + vec2f(o, 0.0), 0.0).rgb;
            wsum += w0 + w1;
        }
        let wl = exp(f32(r * r) * k);
        sum += wl * textureLoad(streaks, clamp(p + vec2i(r, 0), vec2i(0), size - 1), 0).rgb;
        wsum += wl;
        c = sum / wsum;
    }
    gpufx_write(id, vec4f(c, 1.0));
}
