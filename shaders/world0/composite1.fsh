#version 120

#define OUTLINE_WIDTH 1

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D depthtex0;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjection;

varying vec2 texcoord;

vec2 offset(vec2 ori) {
    return vec2(ori.x * OUTLINE_WIDTH / viewWidth, ori.y * OUTLINE_WIDTH / viewHeight);
}

/* DRAWBUFFERS: 0 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).x;

    /* OUTLINE */
    float depth00 = log(texture2D(gdepth, texcoord + offset(vec2(-1, -1))).x);
    float depth01 = log(texture2D(gdepth, texcoord + offset(vec2(0, -1))).x);
    float depth02 = log(texture2D(gdepth, texcoord + offset(vec2(1, -1))).x);
    float depth10 = log(texture2D(gdepth, texcoord + offset(vec2(-1, 0))).x);
    float depth11 = log(texture2D(gdepth, texcoord + offset(vec2(0, 0))).x);
    float depth12 = log(texture2D(gdepth, texcoord + offset(vec2(1, 0))).x);
    float depth20 = log(texture2D(gdepth, texcoord + offset(vec2(-1, 1))).x);
    float depth21 = log(texture2D(gdepth, texcoord + offset(vec2(0, 1))).x);
    float depth22 = log(texture2D(gdepth, texcoord + offset(vec2(1, 1))).x);

    /* _SOBEL */
    // float sobel_h = -1 * depth00 + 1 * depth02 - 2 * depth10 + 2 * depth12 - 1 * depth20 + 1 * depth22;
    // float sobel_v = -1 * depth00 + 1 * depth20 - 2 * depth01 + 2 * depth21 - 1 * depth02 + 1 * depth22;
    // float sobel = sqrt(sobel_h * sobel_h + sobel_v * sobel_v);
    // sobel = sobel > 0.25 ? -1 : 0;

    /* _LAPLACIAN */
    float laplacian = -1 * depth00 - 1 * depth01 - 1 * depth02 - 1 * depth10 + 8 * depth11 - 1 * depth12 - 1 * depth20 - 1 * depth21 - 1 * depth22;
    laplacian = smoothstep(0.1, 0.2, abs(laplacian));

    // color = color * (1 - (depth < 1 ? 0.25 : 0.5) * laplacian) - 0.1 * laplacian;
    color *= laplacian;

    gl_FragData[0] = vec4(color, 1.0);
}