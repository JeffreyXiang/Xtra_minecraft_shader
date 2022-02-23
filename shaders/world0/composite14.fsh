#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SKY_ILLUMINATION_INTENSITY 3.0  //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]

#define OUTLINE_ENABLE 1 // [0 1]
#define OUTLINE_WIDTH 1

#define AIR_DECAY 0.001     //[0.0001 0.0002 0.0005 0.001 0.002 0.005 0.01]

#define WATER_DECAY 0.1     //[0.01 0.02 0.05 0.1 0.2 0.5 1.0]

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D colortex8;

uniform ivec2 eyeBrightnessSmooth;
uniform float sunAngle;
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

/* DRAWBUFFERS: 0 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;

    float sun_angle = sunAngle < 0.5 ? 0.5 - 2 * abs(sunAngle - 0.25) : 0;
    float sky_light_mix = smoothstep(0, 0.02, sun_angle);
    float sky_brightness = SKY_ILLUMINATION_INTENSITY * mix(0.005, 1, sky_light_mix);

    /* EXPOSURE ADJUST */
    float eye_brightness = sky_brightness * (eyeBrightnessSmooth.y) / 240.0;
    color *= clamp(2 / eye_brightness, 0, 1);

    /* GAMMA */
    color = pow(color, vec3(1 / GAMMA));

#if OUTLINE_ENABLE
    float dist = texture2D(gdepth, texcoord).x;
    if (dist < far) {
        /* OUTLINE */
        float depth00 = log(texture2D(gdepth, texcoord + offset(vec2(-OUTLINE_WIDTH, -OUTLINE_WIDTH))).x);
        float depth01 = log(texture2D(gdepth, texcoord + offset(vec2(0, -OUTLINE_WIDTH))).x);
        float depth02 = log(texture2D(gdepth, texcoord + offset(vec2(OUTLINE_WIDTH, -OUTLINE_WIDTH))).x);
        float depth10 = log(texture2D(gdepth, texcoord + offset(vec2(-OUTLINE_WIDTH, 0))).x);
        float depth11 = log(texture2D(gdepth, texcoord + offset(vec2(0, 0))).x);
        float depth12 = log(texture2D(gdepth, texcoord + offset(vec2(OUTLINE_WIDTH, 0))).x);
        float depth20 = log(texture2D(gdepth, texcoord + offset(vec2(-OUTLINE_WIDTH, OUTLINE_WIDTH))).x);
        float depth21 = log(texture2D(gdepth, texcoord + offset(vec2(0, OUTLINE_WIDTH))).x);
        float depth22 = log(texture2D(gdepth, texcoord + offset(vec2(OUTLINE_WIDTH, OUTLINE_WIDTH))).x);

        /* _SOBEL */
        // float sobel_h = -1 * depth00 + 1 * depth02 - 2 * depth10 + 2 * depth12 - 1 * depth20 + 1 * depth22;
        // float sobel_v = -1 * depth00 + 1 * depth20 - 2 * depth01 + 2 * depth21 - 1 * depth02 + 1 * depth22;
        // float sobel = sqrt(sobel_h * sobel_h + sobel_v * sobel_v);
        // sobel = sobel > 0.25 ? -1 : 0;

        /* _LAPLACIAN */
        float laplacian = -1 * depth00 - 1 * depth01 - 1 * depth02 - 1 * depth10 + 8 * depth11 - 1 * depth12 - 1 * depth20 - 1 * depth21 - 1 * depth22;
        laplacian = smoothstep(0.1, 0.2, abs(laplacian));

        if (isEyeInWater == 1) 
            color = clamp(color - mix(vec3(0.0), 0.5 * laplacian * color + 0.1 * laplacian, fog(dist, 4 * WATER_DECAY)), 0, 100);
        else
            color = clamp(color - mix(vec3(0.0), 0.5 * laplacian * color + 0.1 * laplacian, fog(dist, 4 * AIR_DECAY)), 0, 100);
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