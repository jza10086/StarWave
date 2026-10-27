shader_type canvas_item;
render_mode unshaded;
uniform float drift = 0.0;

// Original analytic atmosphere: broad transparent-looking blue strata, not a
// circular playfield or a bloom overlay. All motion is driven by the V toggle.
float field(vec2 p, vec2 scale) {
    vec2 q = p * scale;
    return exp(-dot(q, q));
}

float ghost_world(vec2 uv, vec2 center, float radius, float aspect) {
    vec2 p = (uv - center) * vec2(aspect, 1.0) / radius;
    float r = length(p);
    float disc = 1.0 - smoothstep(0.97, 1.01, r);
    float limb = exp(-pow((r - 0.94) / 0.045, 2.0));
    // Extremely faint, broken cloudy strata: these are distant ghosts, not
    // solid shaded objects or rings a player might mistake for a hazard.
    float cloud = 0.5 + 0.25 * sin(p.y * 17.0 + sin(p.x * 11.0) * 1.8)
        + 0.15 * sin(p.y * 33.0 - p.x * 13.0);
    float fade = smoothstep(-0.8, 0.8, -p.x - p.y * 0.5);
    return disc * cloud * fade * 0.32 + limb * fade * 0.38;
}

void fragment() {
    vec2 uv = UV;
    float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
    float sway = sin(drift * 0.018) * 0.025;
    float blue = field(uv - vec2(0.49 + sway, 0.48), vec2(2.0, 1.25));
    float violet = field(uv - vec2(0.83, 0.22 + sway), vec2(2.7, 2.0));
    float lower = field(uv - vec2(0.2, 0.93), vec2(2.5, 2.8));
    // A wide diagonal veil introduces depth without any arena-shaped edge.
    float veil = exp(-pow((uv.x - 0.26 - uv.y * 0.29 + sway) * 4.0, 2.0));
    vec3 col = vec3(0.022, 0.016, 0.075)
        + blue * vec3(0.055, 0.090, 0.245)
        + violet * vec3(0.061, 0.014, 0.095)
        + lower * vec3(0.020, 0.013, 0.068)
        + veil * vec3(0.004, 0.013, 0.028);
    float worlds = ghost_world(uv, vec2(0.15, 0.76), 0.125, aspect)
        + ghost_world(uv, vec2(0.87, 0.30), 0.085, aspect) * 0.7
        + ghost_world(uv, vec2(0.73, 1.03), 0.19, aspect) * 0.6;
    col += worlds * vec3(0.048, 0.035, 0.105);
    // Sub-LSB dither keeps smooth alpha-like fields free of 8-bit banding.
    float noise = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
    COLOR = vec4(col + (noise - 0.5) / 255.0, 1.0);
}
