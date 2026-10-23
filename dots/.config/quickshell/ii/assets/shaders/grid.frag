#version 440
// Animated wallpaper (services/ShaderWallpaper.qml). Colors: color1..3 accents, color4 the background.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;
    vec4 color1;
    vec4 color2;
    vec4 color3;
    vec4 color4;
};

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

// A neon grid running towards a striped sun on the horizon
void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = resolution.x / max(resolution.y, 1.0);
    vec2 p = vec2((uv.x - 0.5) * aspect, 1.0 - uv.y);
    float horizon = 0.4;
    vec3 col;
    if (p.y > horizon) {
        float k = (p.y - horizon) / (1.0 - horizon);
        col = mix(color1.rgb * 0.9, color4.rgb, pow(k, 0.6));
        float star = step(0.998, hash(floor(uv * 300.0))) * smoothstep(0.3, 0.9, k);
        col += star * 0.7;
        vec2 sc = vec2(0.0, horizon + 0.21);
        float r = length(p - sc);
        float sunR = 0.22;
        if (r < sunR) {
            float sk = clamp((p.y - (sc.y - sunR)) / (2.0 * sunR), 0.0, 1.0);
            vec3 sun = mix(color1.rgb, color2.rgb, sk);
            float gap = step(0.62, fract((sc.y - p.y) * 30.0 + time * 0.25)) * step(p.y, sc.y);
            gap *= smoothstep(sc.y, sc.y - sunR, p.y) * 1.4;
            col = mix(sun, col, clamp(gap, 0.0, 1.0));
        }
        col += color2.rgb * 0.35 * exp(-r * 3.5);
    } else {
        float d = horizon - p.y;
        float z = 0.3 / max(d, 0.002);
        float gz = fract(z - time * 0.5);
        float gx = fract(p.x * z * 0.9);
        float lw = clamp(0.035 * z, 0.0, 0.45);
        float lineZ = smoothstep(lw, 0.0, min(gz, 1.0 - gz));
        float lineX = smoothstep(lw * 0.7, 0.0, min(gx, 1.0 - gx));
        float fade = smoothstep(0.0, 0.2, d);
        col = color4.rgb * 0.35 + color1.rgb * 0.08;
        col += color3.rgb * max(lineZ, lineX) * (0.35 + 0.9 * fade);
        col += color1.rgb * 0.45 * exp(-d * 12.0);
    }
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
