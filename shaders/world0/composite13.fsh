#version 120

#define PI 3.1415926535898
#define PHI 0.6180339887498949

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define MOON_INTENSITY 2e-5
#define SUN_SRAD 2e1
#define MOON_SRAD 5e1

#define DOF_ENABLE 1 // [0 1]
#define DOF_INTENSITY 10 // [1 2 5 10 15 20 25 30 35 40 45 50 100]
#define DOF_MAX_RADIUS 8
#define DOF_SAMPLE_NUM 32 // [1 2 4 8 16 32 64 128 256]

#define SKY_ILLUMINATION_INTENSITY 20.0  //[5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]

#define EXPOSURE 1.0 //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define AUTO_EXPOSURE_ENABLE 1 // [0 1]
#define TONEMAP_ENABLE 1 // [0 1]
#define TONE_R 1.0 //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define TONE_G 1.0 //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define TONE_B 1.0 //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

#define OUTLINE_ENABLE 1 // [0 1]
#define OUTLINE_WIDTH 1

#define FOG_AIR_DECAY 1e-4      //[0.0 1e-5 2e-5 5e-5 1-e4 2e-4 5e-4 0.001 0.002 0.005 0.01 0.02 0.05]
#define FOG_AIR_DECAY_RAIN 0.005 //[0.0 1e-5 2e-5 5e-5 1-e4 2e-4 5e-4 0.001 0.002 0.005 0.01 0.02 0.05]
#define FOG_WATER_DECAY 0.1     //[0.01 0.02 0.05 0.1 0.2 0.5 1.0]

#define BLOOM_ENABLE 1 // [0 1]
#define BLOOM_INTENSITY 1 // [0.2 0.5 1 1.2 1.5 2 5]

#define LUT_WIDTH 512
#define LUT_HEIGHT 512

uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux2;
uniform sampler2D gaux4;
uniform sampler2D colortex8;
uniform sampler2D colortex15;

#if DOF_ENABLE
const bool gcolorMipmapEnabled = true;
const bool compositeMipmapEnabled = true;
#endif

varying vec2 texcoord;

uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform int isEyeInWater;
uniform float centerDepthSmooth;
uniform ivec2 eyeBrightnessSmooth;
uniform vec3 sunPosition;
uniform float rainStrength;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

vec2 offset(vec2 ori) {
    return vec2(ori.x / viewWidth, ori.y / viewHeight);
}

vec2 nearest(vec2 texcoord) {
    return vec2((floor(texcoord.s * viewWidth) + 0.5) / viewWidth, (floor(texcoord.t * viewHeight) + 0.5) / viewHeight);
}

float grayscale(vec3 color) {
    return color.r * 0.299 + color.g * 0.587 + color.b * 0.114;
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

vec3 screen_coord_to_view_coord(vec3 screen_coord) {
    vec4 ndc_coord = vec4(screen_coord * 2 - 1, 1);
    vec4 clip_coord = gbufferProjectionInverse * ndc_coord;
    vec3 view_coord = clip_coord.xyz / clip_coord.w;
    return view_coord;
}

vec3 view_coord_to_world_coord(vec3 view_coord) {
    vec3 world_coord = (gbufferModelViewInverse * vec4(view_coord, 1.0)).xyz;
    return world_coord;
}

vec3 LUT_sky_light() {
    vec2 uv = vec2(32.5 / LUT_WIDTH,
                   98.5 / LUT_HEIGHT);
    return texture2D(colortex15, uv).rgb;
}

vec3 jodieReinhardTonemap(vec3 c){
    // From: https://www.shadertoy.com/view/tdSXzD
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    vec3 tc = c / (c + 1.0);
    return mix(c / (l + 1.0), tc, tc);
}

vec2 Fibonacci_disk_sample(int n, int total) {
    float theta = 2 * PI * fract(PHI * n);
    float r = sqrt(float(n) / total);
    return vec2(r * cos(theta), r * sin(theta));
}

/* RENDERTARGETS: 0 */
void main() {
    vec4 color_data = texture2D(gcolor, texcoord);
    vec3 color = color_data.rgb;
    vec4 color_g = texture2D(composite, texcoord);
    vec4 dist_data = texture2D(gaux4, texcoord);
    float dist = dist_data.x;
    float dist_g = dist_data.z;
    float s;

    /* DOF */
    #if DOF_ENABLE
    float center_depth_smooth = -screen_coord_to_view_coord(vec3(0.5, 0.5, centerDepthSmooth)).z;
    float dof_radius = dist > center_depth_smooth ? min(DOF_MAX_RADIUS, DOF_INTENSITY / center_depth_smooth * abs(dist - center_depth_smooth) / dist) : 0,
        dof_radius_g = dist_g > center_depth_smooth ? min(DOF_MAX_RADIUS, DOF_INTENSITY / center_depth_smooth * abs(dist_g - center_depth_smooth) / dist_g) : 0;
    if (texture2D(gaux2, texcoord / 4 + vec2(0, 0.75)).a == 0) dof_radius_g = 0;
    int dof_sample_num = int(ceil(DOF_SAMPLE_NUM * dof_radius / DOF_MAX_RADIUS));
    vec2 dof_sample_texcoord;
    int dof_cnt = 1, dof_cnt_g = 1; float dof_sample_dist, dof_sample_radius, level = log(1 + 2 * dof_radius / sqrt(dof_sample_num));
    for (int i = 1; i < dof_sample_num; i++) {
        float theta = 2 * PI * fract(PHI * i);
        float r = sqrt(float(i) / dof_sample_num);
        dof_sample_texcoord = texcoord + offset(dof_radius * vec2(r * cos(theta), r * sin(theta)));
        dof_sample_dist = texture2D(gaux4, dof_sample_texcoord).x;
        dof_sample_radius = dof_sample_dist > center_depth_smooth ? 
            min(DOF_MAX_RADIUS, DOF_INTENSITY / center_depth_smooth * abs(dof_sample_dist - center_depth_smooth)) :
            0;
        if (dof_sample_radius > dof_radius * 0.8) {
            color += texture2D(gcolor, dof_sample_texcoord, level).rgb;
            dof_cnt++;
        }
        if (r * dof_radius < dof_radius_g) {
            color_g += texture2D(composite, dof_sample_texcoord, level);
            dof_cnt_g++;
        }
    }
    color /= dof_cnt;
    color_g /= dof_cnt_g;

    s = 1;
    vec4 dof_color = vec4(0.0);
    for (int i = 2; i < 5; i++) {
        s *= 0.5;
        vec4 dof_color_layer = texture2D(gnormal, texcoord * s + vec2(1 - 2 * s, mod(i, 2) == 0 ? 0 : 0.75));
        dof_color.a += dof_color_layer.a;
        dof_color.rgb += dof_color_layer.a * dof_color_layer.rgb;
        color_g += texture2D(gaux2, texcoord * s + vec2(1 - 2 * s, mod(i, 2) == 0 ? 0 : 0.75));
    }
    float k = min(1, dof_color.a * 6) / (dof_color.a + 1e-6);
    dof_color *= k;
    dof_color.rgb += (1 - dof_color.a) * color;
    color = (1 - dof_color.a) * color + dof_color.a * dof_color.rgb;
    #endif

    color = (1 - min(1, color_g.a)) * color + color_g.rgb;

    vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
    float sky_brightness = SKY_ILLUMINATION_INTENSITY * grayscale(LUT_sky_light());

    /* EXPOSURE ADJUST */
    #if AUTO_EXPOSURE_ENABLE
    float eye_brightness = (isEyeInWater == 1 ? 1 : eyeBrightnessSmooth.y / 240.0);
    eye_brightness = sky_brightness * eye_brightness * eye_brightness;
    color *= clamp(0.2 / eye_brightness, 0.25, 10);
    #endif

    color *= pow(EXPOSURE, GAMMA) * vec3(TONE_R, TONE_G, TONE_B);

    #if TONEMAP_ENABLE
    /* TONEMAP */
    color = jodieReinhardTonemap(color);
    #endif
    
    /* GAMMA */
    color = pow(color, vec3(1 / GAMMA));

    #if OUTLINE_ENABLE
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
        else {
            float fog_air_decay = mix(FOG_AIR_DECAY, FOG_AIR_DECAY_RAIN, rainStrength);
            color = clamp(color - mix(vec3(0.0), 0.5 * laplacian * color + 0.1 * laplacian, fog(dist, 4 * fog_air_decay)), 0, 100);
        }
    }
    #endif

    /* BLOOM */
    #if BLOOM_ENABLE
    vec3 bloom = vec3(0.0);
    s = 1;
    for (int i = 2; i < 5; i++) {
        s *= 0.5;
        bloom += texture2D(colortex8, texcoord * s + vec2(1 - 2 * s, mod(i, 2) == 0 ? 0 : 0.75)).rgb / (32 * s);
    }
    color += BLOOM_INTENSITY * bloom;
    #endif

    gl_FragData[0] = vec4(color, 1.0);
}