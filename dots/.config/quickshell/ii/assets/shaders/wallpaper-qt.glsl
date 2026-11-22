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

vec4 wallpaper(vec2 uv);
void main() {
    fragColor = wallpaper(qt_TexCoord0) * qt_Opacity;
}
