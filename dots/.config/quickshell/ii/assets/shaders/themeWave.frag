#version 440
// Theme transition (modules/common/panels/ThemeTransitionOverlay.qml): the picture of the screen from before
// a change, with a soft-edged hole growing from `origin` that shows the screen after it. A faint rim in the
// new accent color runs along the edge, so the wave reads as the new look arriving.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution; // Size of the picture, in logical pixels
    vec2 origin;     // Middle of the hole, in this picture's coordinates (may be off this screen)
    float radius;    // Of the hole, to the middle of its soft edge
    float feather;   // Half the width of the soft edge
    float progress;  // 0..1, fades the rim out before the last corners go
    vec4 rimColor;
    float rim;       // Strength of the rim, 0 for none
};
layout(binding = 1) uniform sampler2D source;

void main() {
    float distanceToOrigin = length(qt_TexCoord0 * resolution - origin);
    float keep = smoothstep(radius - feather, radius + feather, distanceToOrigin);
    vec4 picture = texture(source, qt_TexCoord0) * keep;
    float band = (distanceToOrigin - radius) / feather;
    float glow = rim * exp(-band * band * 1.5) * (1.0 - smoothstep(0.75, 1.0, progress)) * (1.0 - picture.a);
    fragColor = (picture + vec4(rimColor.rgb, 1.0) * glow) * qt_Opacity;
}
