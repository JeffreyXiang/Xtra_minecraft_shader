#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SHADOW_EPSILON 1e-1
#define SHADOW_INTENSITY 0.5    // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SHADOW_FISHEY_LENS_INTENSITY 0.85

#define ILLUMINATION_EPSILON 0.5
#define ILLUMINATION_MODE 0     // [0 1]
#define BLOCK_ILLUMINATION_COLOR_TEMPERATURE 4400   // [2400 2800 3200 3600 4000 4400 4800 5200 5600 6000 6400 6800 7200]
#if BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 2400
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.3364, 0.0501), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 2800
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.4195, 0.1119), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 3200
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.4970, 0.1879), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 3600
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.5689, 0.2745), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 4000
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.6354, 0.3684), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 4400
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.6966, 0.4668), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 4800
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.7528, 0.5675), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 5200
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.8044, 0.6685), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 5600
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.8518, 0.7686), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 6000
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.8952, 0.8666), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 6400
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(1.0000, 0.9351, 0.9616), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 6800
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(0.9488, 0.9219, 1.0501), vec3(GAMMA))
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 7200
    #define BLOCK_ILLUMINATION_COLOR pow(vec3(0.8753, 0.8799, 1.0501), vec3(GAMMA))
#endif
#define BLOCK_ILLUMINATION_CLASSIC_INTENSITY 1.5    //[0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.25 2.5]
#define BLOCK_ILLUMINATION_PHYSICAL_INTENSITY 3.0   //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#define BLOCK_ILLUMINATION_PHYSICAL_CLOSEST 0.5    //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SKY_ILLUMINATION_INTENSITY 3.0  //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#define BASE_ILLUMINATION_INTENSITY 0.01  //[0.001 0.002 0.005 0.01 0.02 0.05 0.1]

#define SSAO_ENABLE 1 // [0 1]

#define SKYLIGHT_WATER_DECAY 1

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;

uniform float far;
uniform vec3 shadowLightPosition;
uniform float sunAngle;
uniform int isEyeInWater;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

varying vec2 texcoord;

vec2 fish_len_distortion(vec2 ndc_coord_xy) {
    float dist = length(ndc_coord_xy);
    float distort = (1.0 - SHADOW_FISHEY_LENS_INTENSITY ) + dist * SHADOW_FISHEY_LENS_INTENSITY;
    return ndc_coord_xy.xy / distort;
}

vec3 screen_coord_to_view_coord(vec3 screen_coord) {
    vec4 ndc_coord = vec4(screen_coord * 2 - 1, 1);
    vec4 clid_coord = gbufferProjectionInverse * ndc_coord;
    vec3 view_coord = clid_coord.xyz / clid_coord.w;
    return view_coord;
}

vec3 view_coord_to_world_coord(vec3 view_coord) {
    vec3 world_coord = (gbufferModelViewInverse * vec4(view_coord, 1.0)).xyz;
    return world_coord;
}

vec3 world_coord_to_shadow_coord(vec3 world_coord) {
    vec4 shadow_view_coord = shadowModelView * vec4(world_coord, 1);
    // shadow_view_coord.z += SHADOW_EPSILON;
    vec4 shadow_clip_coord = shadowProjection * shadow_view_coord;
    vec4 shadow_ndc_coord = vec4(shadow_clip_coord.xyz / shadow_clip_coord.w, 1.0);
    vec3 shadow_screen_coord = shadow_ndc_coord.xyz * 0.5 + 0.5;
    return shadow_screen_coord;
}

float fog(float dist, float decay) {
    dist -= 1;
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
    vec4 color_data = texture2D(gcolor, texcoord);
    vec3 color = color_data.rgb;
    float alpha = color_data.a;
    float depth1 = texture2D(depthtex1, texcoord).x;
    vec4 normal_data0 = texture2D(gnormal, texcoord);
    vec3 normal0 = normal_data0.xyz;
    float block_id0 = normal_data0.w;
    float block_id1 = texture2D(gaux1, texcoord).w;
    vec4 lumi_data = texture2D(gaux2, texcoord);

    /* SHADOW */
    float sun_light_shadow = 0.0;
    float in_shadow = 0.0;
    vec2 shadow_texcoord;
    float current_depth;
    if (block_id0 > 0.5) {
        vec3 screen_coord = vec3(texcoord, depth1);
        vec3 view_coord = screen_coord_to_view_coord(screen_coord);
        view_coord += SHADOW_EPSILON * normal0;
        vec3 world_coord = view_coord_to_world_coord(view_coord);
        vec3 light_direction = normalize(view_coord - 10 * shadowLightPosition);
        vec3 shadow_coord = world_coord_to_shadow_coord(world_coord);
        float shadow_dist = length(world_coord);
        float shadow_dist_weight = 1 - smoothstep(0.6, 0.7, shadow_dist / far);
        current_depth = shadow_coord.z;
        shadow_texcoord = fish_len_distortion(shadow_coord.xy * 2 - 1) * 0.5 + 0.5;
        float closest_depth = texture2D(shadowtex1, shadow_texcoord).x;
        float k = dot(light_direction, normal0);
        sun_light_shadow = 1 - smoothstep(-0.05, 0.0, k);
        in_shadow = (current_depth >= closest_depth || k > 0) ? 1 : 0;
        sun_light_shadow *= 1 - in_shadow;
        sun_light_shadow = 1 - sun_light_shadow;
        sun_light_shadow *= shadow_dist_weight;
    }

    /* ILLUMINATION */
    float sun_angle = sunAngle < 0.25 ? 0.25 - sunAngle : sunAngle < 0.75 ? sunAngle - 0.25 : 1.25 - sunAngle;
    sun_angle = 1 - 4 * sun_angle;
    float sun_angle_ = sun_angle < 0 ? 0 : sun_angle;
    vec3 sun_light = pow(vec3(
        (exp(0.01 - 0.01 / (sin(PI * (0.05 + 0.45 * sun_angle_))))),
        (exp(0.1 - 0.1  / (sin(PI * (0.05 + 0.45 * sun_angle_))))),
        (exp(0.3 - 0.3  / (sin(PI * (0.05 + 0.45 * sun_angle_)))))
    ), vec3(GAMMA));
    vec3 moon_light = vec3(0.005);
    float sky_light_mix = smoothstep(-0.05, 0.2, sun_angle);
    vec3 sky_light = SKY_ILLUMINATION_INTENSITY * mix(moon_light, sun_light, sky_light_mix);
    float sky_brightness = SKY_ILLUMINATION_INTENSITY * mix(0.005, 1, sky_light_mix);
    float sunmoon_light_mix = smoothstep(0, 0.2, sun_angle);
    vec3 sunmoon_light = SKY_ILLUMINATION_INTENSITY * mix(moon_light, sun_light, sunmoon_light_mix);
    if (isEyeInWater == 0 && block_id1 > 1.5 || isEyeInWater == 1 && block_id1 < 1.5) {
        float shadow_water_dist = -((current_depth - texture2D(shadowtex0, shadow_texcoord).x) * 2 - 1 - shadowProjection[3][2]) / shadowProjection[2][2];
        shadow_water_dist = shadow_water_dist < 0 ? 0 : shadow_water_dist;
        float k = fog(shadow_water_dist, SKYLIGHT_WATER_DECAY);
        sky_light *= k;
        sunmoon_light *= k;
    } 

    if (block_id0 > 0.5) {
        #if ILLUMINATION_MODE
            vec3 block_light = BLOCK_ILLUMINATION_CLASSIC_INTENSITY * lumi_data.x * BLOCK_ILLUMINATION_COLOR;
        #else
            float block_light_dist = block_id0 > 1.5 ? 0 : 13 - clamp(15 * lumi_data.x - 1, 0, 13);
            block_light_dist = (1 - ILLUMINATION_EPSILON) * block_light_dist + ILLUMINATION_EPSILON * block_light_dist / (13 - block_light_dist) + BLOCK_ILLUMINATION_PHYSICAL_CLOSEST;
            vec3 block_light = BLOCK_ILLUMINATION_PHYSICAL_INTENSITY * BLOCK_ILLUMINATION_PHYSICAL_CLOSEST * BLOCK_ILLUMINATION_PHYSICAL_CLOSEST / (block_light_dist * block_light_dist) * BLOCK_ILLUMINATION_COLOR;
        #endif

        sky_light *= (in_shadow > 0.5 ? lumi_data.y : 1) * (1 - SHADOW_INTENSITY);
        sunmoon_light *= (1 - sun_light_shadow) * SHADOW_INTENSITY;
        color *= block_light + sky_light + sunmoon_light + BASE_ILLUMINATION_INTENSITY;
        #if SSAO_ENABLE
            color *= lumi_data.z;   // SSAO
        #endif
    }
    else {
        color *= clamp(sky_brightness / 2, 1, 100);
    }
    
    gl_FragData[0] = vec4(color, alpha);
}