// Layers of dunes or hills drifting at different speeds under a low sun
vec4 wallpaper(vec2 uv) {
    float aspect = resolution.x / max(resolution.y, 1.0);
    vec2 p = vec2(uv.x * aspect, 1.0 - uv.y);
    float t = time * 0.05;
    vec3 col = mix(color2.rgb, color4.rgb, smoothstep(0.25, 1.0, p.y));
    vec2 sc = vec2(aspect * 0.7, 0.66);
    float r = length(p - sc);
    col += color1.rgb * 0.55 * exp(-r * 4.5);
    col = mix(col, mix(color1.rgb, vec3(1.0), 0.45), smoothstep(0.078, 0.072, r));
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float base = 0.56 - fi * 0.11;
        float speed = 0.3 + fi * 0.3;
        float h = base + 0.05 * sin(p.x * (1.4 + fi * 0.6) + t * speed * 6.0 + fi * 2.0)
                       + 0.025 * sin(p.x * (3.7 + fi) - t * speed * 4.0 + fi);
        vec3 layer = mix(color3.rgb, color4.rgb * 0.25, fi / 4.0);
        layer = mix(layer, color1.rgb, 0.2 * (1.0 - fi / 4.0));
        col = mix(col, layer, smoothstep(h + 0.003, h - 0.003, p.y));
    }
    return vec4(col, 1.0);
}
