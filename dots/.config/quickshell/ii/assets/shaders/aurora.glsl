// Northern lights: three swaying curtains over a starry sky and dark hills
vec4 wallpaper(vec2 uv) {
    float aspect = resolution.x / max(resolution.y, 1.0);
    vec2 p = vec2(uv.x * aspect, 1.0 - uv.y);
    float t = time * 0.05;
    vec3 col = mix(color4.rgb * 1.25, color4.rgb * 0.35, smoothstep(0.0, 1.0, p.y));
    float star = step(0.9975, hash(floor(p * 260.0))) * smoothstep(0.35, 1.0, p.y);
    col += star * (0.5 + 0.5 * sin(time * 2.0 + hash(floor(p * 260.0)) * 30.0));
    vec3 lights = vec3(0.0);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float sway = fbm(vec2(p.x * 1.1 + fi * 3.1, t * 2.0 + fi));
        float center = 0.5 + 0.12 * fi + 0.28 * (sway - 0.5) + 0.05 * sin(p.x * 2.0 + t * 6.0 + fi);
        float d = p.y - center;
        float band = exp(-d * d * 70.0);
        float rise = smoothstep(-0.02, 0.2, d) * exp(-max(d, 0.0) * 5.0);
        float rays = 0.5 + 0.5 * fbm(vec2(p.x * 9.0 + t * 3.0 + fi * 10.0, p.y * 1.2));
        vec3 c = i == 0 ? color1.rgb : (i == 1 ? color2.rgb : color3.rgb);
        lights += c * (band * 0.85 + rise * 0.55) * rays;
    }
    // Where curtains overlap they get brighter, not white: scaled by the strongest channel, the hue stays
    col += 1.6 * lights / (1.0 + 0.6 * max(max(lights.r, lights.g), lights.b));
    float hill = 0.13 + 0.05 * sin(p.x * 2.6 + 1.0) + 0.025 * sin(p.x * 7.3 + 2.0);
    col = mix(col, color4.rgb * 0.12, smoothstep(hill + 0.004, hill - 0.004, p.y));
    return vec4(col, 1.0);
}
