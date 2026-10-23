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

// A slow liquid gradient: three colored pools drifting through each other
void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = resolution.x / max(resolution.y, 1.0);
    vec2 p = vec2(uv.x * aspect, uv.y);
    float t = time * 0.08;
    vec2 q = p + 0.18 * vec2(fbm(p * 1.4 + t), fbm(p * 1.4 - t + 4.0)) - 0.09;
    vec2 c1 = vec2(aspect * (0.28 + 0.2 * sin(t * 1.3)), 0.3 + 0.2 * cos(t * 1.1));
    vec2 c2 = vec2(aspect * (0.72 + 0.18 * cos(t * 0.9)), 0.42 + 0.25 * sin(t * 1.7));
    vec2 c3 = vec2(aspect * (0.5 + 0.3 * sin(t * 0.7 + 2.0)), 0.78 + 0.14 * cos(t * 1.2));
    float w1 = 1.0 / (0.02 + dot(q - c1, q - c1));
    float w2 = 1.0 / (0.02 + dot(q - c2, q - c2));
    float w3 = 1.0 / (0.02 + dot(q - c3, q - c3));
    float w4 = 1.6;
    vec3 col = (color1.rgb * w1 + color2.rgb * w2 + color3.rgb * w3 + color4.rgb * w4) / (w1 + w2 + w3 + w4);
    col += 0.04 * sin(9.0 * (q.x + q.y) + t * 5.0);
    col = clamp(mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, 1.3), 0.0, 1.0); // A little more saturated
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
