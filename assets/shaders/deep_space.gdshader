shader_type canvas_item;
render_mode unshaded;
uniform float drift = 0.0;
void fragment() {
    vec2 uv = UV;
    vec2 p = uv - vec2(0.52, 0.43);
    float blue = exp(-dot(p * vec2(1.8, 1.45), p * vec2(1.8, 1.45)) * 2.6);
    vec2 q = uv - vec2(0.8 + sin(drift * 0.025) * 0.04, 0.2);
    float violet = exp(-dot(q * vec2(2.2, 1.8), q * vec2(2.2, 1.8)) * 2.0);
    vec2 s = uv - vec2(0.17, 0.83);
    float teal = exp(-dot(s * vec2(2.2, 2.0), s * vec2(2.2, 2.0)) * 3.0);
    vec3 col = vec3(0.018, 0.020, 0.065) + blue * vec3(0.043, 0.060, 0.18)
        + violet * vec3(0.067, 0.018, 0.10) + teal * vec3(0.0, 0.027, 0.033);
    // Sub-LSB ordered noise prevents visible 8-bit gradient bands.
    float noise = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898,78.233))) * 43758.5453);
    COLOR = vec4(col + (noise - 0.5) / 255.0, 1.0);
}
