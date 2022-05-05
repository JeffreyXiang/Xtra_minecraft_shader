#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define OUTLINE_ENABLE 1 // [0 1]
#define OUTLINE_WIDTH 1

#define FOG_AIR_DECAY 0.001     //[0.0001 0.0002 0.0005 0.001 0.002 0.005 0.01]
#define FOG_WATER_DECAY 0.1     //[0.01 0.02 0.05 0.1 0.2 0.5 1.0]

#define TAA_ENABLE 1 // [0 1]

uniform sampler2D gcolor;
uniform sampler2D gaux4;
uniform sampler2D colortex8;
uniform sampler2D colortex11;
uniform sampler2D colortex12;

uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform int isEyeInWater;

varying vec2 texcoord;

vec2 offset(vec2 ori) {
    return vec2(ori.x / viewWidth, ori.y / viewHeight);
}

float fog(float dist, float decay) {
    dist = dist < 0 ? 0 : dist;
    dist = dist * decay / 16 + 1;
    dist = dist * dist;
    dist = dist * dist;
    dist = dist * dist;
    dist = dist * dist;
    return 1 / dist;
}

vec3 RGB_to_YCgCo(vec3 rgb) {
    float temp = 0.25 * (rgb.r + rgb.b);
    return vec3(temp + 0.5 * rgb.g, -temp + 0.5 * rgb.g, 0.5 * (rgb.r - rgb.b));
}

vec3 YCgCo_to_RGB(vec3 YCgCo) {
    float temp = YCgCo.r - YCgCo.g;
    return vec3(temp + YCgCo.b, YCgCo.r + YCgCo.g, temp - YCgCo.b);
}

vec3 color_clip_to_buffer(sampler2D buffer, vec2 texcoord, vec3 color) {
    color = RGB_to_YCgCo(color);

    vec3 YCoCg_00 = RGB_to_YCgCo(texture2D(gcolor, texcoord + offset(vec2(-1, -1))).rgb);
    vec3 YCoCg_01 = RGB_to_YCgCo(texture2D(gcolor, texcoord + offset(vec2(-1,  0))).rgb);
    vec3 YCoCg_02 = RGB_to_YCgCo(texture2D(gcolor, texcoord + offset(vec2(-1,  1))).rgb);
    vec3 YCoCg_10 = RGB_to_YCgCo(texture2D(gcolor, texcoord + offset(vec2( 0, -1))).rgb);
    vec3 YCoCg_11 = RGB_to_YCgCo(texture2D(gcolor, texcoord + offset(vec2( 0,  0))).rgb);
    vec3 YCoCg_12 = RGB_to_YCgCo(texture2D(gcolor, texcoord + offset(vec2( 0,  1))).rgb);
    vec3 YCoCg_20 = RGB_to_YCgCo(texture2D(gcolor, texcoord + offset(vec2( 1, -1))).rgb);
    vec3 YCoCg_21 = RGB_to_YCgCo(texture2D(gcolor, texcoord + offset(vec2( 1,  0))).rgb);
    vec3 YCoCg_22 = RGB_to_YCgCo(texture2D(gcolor, texcoord + offset(vec2( 1,  1))).rgb);
    vec3 YCoCg_min = min(YCoCg_00, min(YCoCg_01, min(YCoCg_02, min(YCoCg_10, min(YCoCg_11, min(YCoCg_12, min(YCoCg_20, min(YCoCg_21, YCoCg_22))))))));
    vec3 YCoCg_max = max(YCoCg_00, max(YCoCg_01, max(YCoCg_02, max(YCoCg_10, max(YCoCg_11, max(YCoCg_12, max(YCoCg_20, max(YCoCg_21, YCoCg_22))))))));

    vec3 p_clip = 0.5 * (YCoCg_max + YCoCg_min);
    vec3 e_clip = 0.5 * (YCoCg_max - YCoCg_min);

    vec3 v_clip = color - p_clip;
    vec3 v_unit = abs(v_clip / e_clip);
    float k = max(v_unit.x, max(v_unit.y, v_unit.z));

    color = p_clip + v_clip / max(k, 1);
    color = YCgCo_to_RGB(color);

    return color;
}

/* DRAWBUFFERS: 0 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;

    /* TAA */
#if TAA_ENABLE
    vec4 motion_data = texture2D(colortex12, texcoord);
    vec2 texcoord_prev = motion_data.st;
    float has_prev = motion_data.a;
    vec3 color_prev = texture2D(colortex11, texcoord_prev).rgb;
    texcoord_prev.s *= viewWidth;
    texcoord_prev.t *= viewHeight;
    float taa_k = min(1, 0.05 + 0.95 * (
        abs(floor(texcoord_prev.s) - texcoord_prev.s + 0.5) + 
        abs(floor(texcoord_prev.t) - texcoord_prev.t + 0.5)
    ));
    color = vec3(taa_k * color + (1 - taa_k) * color_clip_to_buffer(gcolor, texcoord, color_prev));
#endif

#if OUTLINE_ENABLE
    float dist = texture2D(gaux4, texcoord).x;
    if (dist < far) {
        /* OUTLINE */
        float depth00 = log(texture2D(gaux4, texcoord + offset(vec2(-OUTLINE_WIDTH, -OUTLINE_WIDTH))).x);
        float depth01 = log(texture2D(gaux4, texcoord + offset(vec2(0, -OUTLINE_WIDTH))).x);
        float depth02 = log(texture2D(gaux4, texcoord + offset(vec2(OUTLINE_WIDTH, -OUTLINE_WIDTH))).x);
        float depth10 = log(texture2D(gaux4, texcoord + offset(vec2(-OUTLINE_WIDTH, 0))).x);
        float depth11 = log(texture2D(gaux4, texcoord + offset(vec2(0, 0))).x);
        float depth12 = log(texture2D(gaux4, texcoord + offset(vec2(OUTLINE_WIDTH, 0))).x);
        float depth20 = log(texture2D(gaux4, texcoord + offset(vec2(-OUTLINE_WIDTH, OUTLINE_WIDTH))).x);
        float depth21 = log(texture2D(gaux4, texcoord + offset(vec2(0, OUTLINE_WIDTH))).x);
        float depth22 = log(texture2D(gaux4, texcoord + offset(vec2(OUTLINE_WIDTH, OUTLINE_WIDTH))).x);

        /* _SOBEL */
        // float sobel_h = -1 * depth00 + 1 * depth02 - 2 * depth10 + 2 * depth12 - 1 * depth20 + 1 * depth22;
        // float sobel_v = -1 * depth00 + 1 * depth20 - 2 * depth01 + 2 * depth21 - 1 * depth02 + 1 * depth22;
        // float sobel = sqrt(sobel_h * sobel_h + sobel_v * sobel_v);
        // sobel = sobel > 0.25 ? -1 : 0;

        /* _LAPLACIAN */
        float laplacian = -1 * depth00 - 1 * depth01 - 1 * depth02 - 1 * depth10 + 8 * depth11 - 1 * depth12 - 1 * depth20 - 1 * depth21 - 1 * depth22;
        laplacian = smoothstep(0.1, 0.2, abs(laplacian));

        if (isEyeInWater == 1) 
            color = clamp(color - mix(vec3(0.0), 0.5 * laplacian * color + 0.1 * laplacian, fog(dist, 4 * FOG_WATER_DECAY)), 0, 100);
        else
            color = clamp(color - mix(vec3(0.0), 0.5 * laplacian * color + 0.1 * laplacian, fog(dist, 4 * FOG_AIR_DECAY)), 0, 100);
    }
#endif

    /* BLOOM */
    vec3 bloom = vec3(0.0);
    float s = 1;
    for (int i = 2; i < 8; i++) {
        s *= 0.5;
        bloom += texture2D(colortex8, texcoord * s + vec2(1 - 2 * s, mod(i, 2) == 0 ? 0 : 0.75) + offset(vec2(0.5, 0))).rgb / (64 * s);
    }
    color += bloom;
    
    gl_FragData[0] = vec4(color, 1.0);
}