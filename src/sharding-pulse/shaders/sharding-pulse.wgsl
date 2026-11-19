// The frame splits into a 10x10 grid of tiles that drift apart and surge toward or away from the camera in a diagonal wave, while the first clip dissolves into the second.

// Length of the animation timeline, in milliseconds.
const TIMELINE_MS: f32 = 2000.0;
// Tiles per side.
const GRID: i32 = 10;
// Camera distance from the tile plane (world units; the plane is 10 units across).
const CAM_DIST: f32 = 10.0;
// Half the visible height at the plane: CAM_DIST * tan(53.1 deg / 2).
const HALF_VIEW: f32 = 4.99594;
// Depth a tile reaches at the peak of its pulse (toward or away from the camera).
const PULSE_DEPTH: f32 = 5.0;
// Widest extra spacing between neighbouring tiles.
const GAP_MAX: f32 = 0.25;
// Backdrop seen through the gaps: black, because the in-app render target clears to black (the grey scene background only shows in the browser preview).
const BACKDROP: vec3f = vec3f(0.0, 0.0, 0.0);

// Sine ease-in on a value animated from `a` to `b` between t0 and t0 + len (ms).
fn sine_in(t: f32, t0: f32, len: f32, a: f32, b: f32) -> f32 {
    let x = clamp((t - t0) / len, 0.0, 1.0);
    return mix(a, b, 1.0 - cos(x * 1.5707963));
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
    if (!gpufx_in_bounds(id)) { return; }
    let uv = gpufx_uv(id);
    // Exact clips at the ends, so cutting in and out of the transition never jumps.
    if (params.progress <= 0.0) { gpufx_write(id, vec4f(textureSampleLevel(first, smp, uv, 0.0).rgb, 1.0)); return; }
    if (params.progress >= 1.0) { gpufx_write(id, vec4f(textureSampleLevel(second, smp, uv, 0.0).rgb, 1.0)); return; }
    let t = clamp(params.progress, 0.0, 1.0) * TIMELINE_MS;

    // Spacing opens, then closes again; the blend runs underneath both.
    var gap = sine_in(t, 300.0, 450.0, 0.0, GAP_MAX);
    if (t > 750.0) { gap = sine_in(t, 750.0, 450.0, GAP_MAX, 0.0); }
    let blend = sine_in(t, 300.0, 900.0, 0.0, 1.0);

    // Point on the view plane through this pixel, in world units at depth 0.
    let ray = vec2f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0) * HALF_VIEW;
    let centre = f32(GRID - 1) * 0.5;

    // Tiles on one diagonal (row + col) share their pulse, so evaluate the pulse once per diagonal,
    // then test only the one or two columns whose footprint can hold this pixel at that depth.
    // Ties keep the tile that comes first in row-major order.
    let spread = 1.0 + gap;
    var best_z = -1e9;
    var best_idx = 1000;
    var hit = vec2f(-1.0);
    for (var d = 0; d <= 2 * (GRID - 1); d++) {
        let lag = f32(d) * 40.0;
        let side = select(-1.0, 1.0, (d & 1) == 0);
        var z = sine_in(t, 200.0 + lag, 420.0, 0.0, side * PULSE_DEPTH);
        if (t > 620.0 + lag) { z = sine_in(t, 620.0 + lag, 420.0, side * PULSE_DEPTH, 0.0); }
        if (z < best_z) { continue; }
        let r = ray * ((CAM_DIST - z) / CAM_DIST);
        let c_lo = max(i32(ceil(centre + (r.x - 0.5) / spread - 1e-3)), max(0, d - (GRID - 1)));
        let c_hi = min(i32(floor(centre + (r.x + 0.5) / spread + 1e-3)), min(GRID - 1, d));
        for (var col = c_lo; col <= c_hi; col++) {
            let row = d - col;
            let idx = row * GRID + col;
            if (z == best_z && idx > best_idx) { continue; }
            let fc = f32(col);
            let fr = f32(row);
            let pos = vec2f(fc - centre + (fc - centre) * gap, centre - fr + (centre - fr) * gap);
            let local = r - pos;
            if (abs(local.x) <= 0.5 && abs(local.y) <= 0.5) {
                best_z = z;
                best_idx = idx;
                hit = vec2f((fc + local.x + 0.5) / f32(GRID), (fr + 0.5 - local.y) / f32(GRID));
            }
        }
    }

    var colour = BACKDROP;
    if (hit.x >= 0.0) {
        let a = textureSampleLevel(first, smp, hit, 0.0).rgb;
        let b = textureSampleLevel(second, smp, hit, 0.0).rgb;
        colour = mix(a, b, blend);
    }
    gpufx_write(id, vec4f(colour, 1.0));
}
