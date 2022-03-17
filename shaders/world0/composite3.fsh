#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SHADOW_EPSILON 1e-1
#define SHADOW_INTENSITY 0.5    // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SHADOW_FISHEY_LENS_INTENSITY 0.85

#define ILLUMINATION_EPSILON 0.5
#define ILLUMINATION_MODE 0     // [0 1]
#define BLOCK_ILLUMINATION_COLOR_TEMPERATURE 4400   // [1000 1100 1200 1300 1400 1500 1600 1700 1800 1900 2000 2100 2200 2300 2400 2500 2600 2700 2800 2900 3000 3100 3200 3300 3400 3500 3600 3700 3800 3900 4000 4100 4200 4300 4400 4500 4600 4700 4800 4900 5000 5100 5200 5300 5400 5500 5600 5700 5800 5900 6000 6100 6200 6300 6400 6500 6600 6700 6800 6900 7000 7100 7200 7300 7400 7500 7600 7700 7800 7900 8000 8100 8200 8300 8400 8500 8600 8700 8800 8900 9000 9100 9200 9300 9400 9500 9600 9700 9800 9900 10000]

#define BLOCK_ILLUMINATION_CLASSIC_INTENSITY 1.5    //[0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.25 2.5]
#define BLOCK_ILLUMINATION_PHYSICAL_INTENSITY 3.0   //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#define BLOCK_ILLUMINATION_PHYSICAL_CLOSEST 0.5    //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SKY_ILLUMINATION_INTENSITY 3.0  //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#define BASE_ILLUMINATION_INTENSITY 0.01  //[0.001 0.002 0.005 0.01 0.02 0.05 0.1]

#define SSAO_ENABLE 1 // [0 1]

#define FOG_AIR_DECAY 0.001     //[0.0001 0.0002 0.0005 0.001 0.002 0.005 0.01 0.02 0.05]
#define FOG_THICKNESS 256
#define FOG_WATER_DECAY 0.1     //[0.01 0.02 0.05 0.1 0.2 0.5 1.0]

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D colortex15;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;

uniform float far;
uniform vec3 shadowLightPosition;
uniform float sunAngle;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform ivec2 eyeBrightnessSmooth;
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
    dist = dist < 0 ? 0 : dist;
    dist = dist * decay / 16 + 1;
    dist = dist * dist;
    dist = dist * dist;
    dist = dist * dist;
    dist = dist * dist;
    return 1 / dist;
}

float fog_blend(float k1, float k2, float decay) {
    return mix(k1, k2, 0.5 * sqrt(decay));
}

float grayscale(vec3 color) {
    return color.r * 0.299 + color.g * 0.587 + color.b * 0.114;
}

vec3 LUT_color_temperature(float temp) {
    return texture2D(colortex15, vec2((0.5 + (temp - 1000) / 9000 * 90) / 256, 0.5 / 256)).rgb;
}

vec3 LUT_water_absorption(float decay) {
    return texture2D(colortex15, vec2(1 - decay, 1.5 / 256)).rgb;
}

vec3 LUT_water_scattering(float decay) {
    return texture2D(colortex15, vec2(1 - decay, 2.5 / 256)).rgb;
}

/* DRAWBUFFERS: 03678 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;
    vec4 translucent_data = texture2D(composite, texcoord);
    vec3 translucent = translucent_data.rgb;
    float alpha = translucent_data.a;
    float depth1 = texture2D(depthtex1, texcoord).x;
    vec4 dist_data = texture2D(gdepth, texcoord);
    float dist0 = dist_data.x;
    float dist1 = dist_data.y;
    vec4 normal_data0 = texture2D(gnormal, texcoord);
    vec3 normal0 = normal_data0.xyz;
    float block_id0 = normal_data0.w;
    float block_id1 = texture2D(gaux1, texcoord).w;
    vec4 lumi_data = texture2D(gaux2, texcoord);
    vec3 block_illumination_color = LUT_color_temperature(BLOCK_ILLUMINATION_COLOR_TEMPERATURE);

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
        float k = fog(shadow_water_dist * normalize(view_coord_to_world_coord(shadowLightPosition)).y, FOG_WATER_DECAY);
        sky_light *= k * LUT_water_absorption(k);
        k = fog(shadow_water_dist, FOG_WATER_DECAY);
        sunmoon_light *= k * LUT_water_absorption(k);
    } 

    if (block_id0 > 0.5) {
        #if ILLUMINATION_MODE
            vec3 block_light = BLOCK_ILLUMINATION_CLASSIC_INTENSITY * lumi_data.x * block_illumination_color;
        #else
            float block_light_dist = block_id0 > 1.5 ? 0 : 13 - clamp(15 * lumi_data.x - 1, 0, 13);
            block_light_dist = (1 - ILLUMINATION_EPSILON) * block_light_dist + ILLUMINATION_EPSILON * block_light_dist / (13 - block_light_dist) + BLOCK_ILLUMINATION_PHYSICAL_CLOSEST;
            vec3 block_light = BLOCK_ILLUMINATION_PHYSICAL_INTENSITY * BLOCK_ILLUMINATION_PHYSICAL_CLOSEST * BLOCK_ILLUMINATION_PHYSICAL_CLOSEST / (block_light_dist * block_light_dist) * block_illumination_color;
        #endif

        float k = fog(FOG_THICKNESS, FOG_AIR_DECAY);
        sky_light *= (in_shadow > 0.5 ? lumi_data.y : 1) * (1 - SHADOW_INTENSITY * k);
        sunmoon_light *= (1 - sun_light_shadow) * SHADOW_INTENSITY * k;
        color *= block_light + sky_light + sunmoon_light + BASE_ILLUMINATION_INTENSITY;
        #if SSAO_ENABLE
            color *= lumi_data.z;   // SSAO
        #endif
    }
    else {
        color *= clamp(sky_brightness / 2, 1, 100);
    }

    /* FOG */
    lumi_data.z = eyeBrightnessSmooth.y / 240.;
    vec3 fog_color = pow(fogColor, vec3(GAMMA)) * lumi_data.z;
    fog_color *= clamp(sky_brightness / 2, 1, 100);
    vec3 sky_color = pow(skyColor, vec3(GAMMA)) * lumi_data.w;
    float fog_decay0, fog_decay1;
    vec3 fog_scatter0 = translucent, fog_scatter1 = color;
    if (isEyeInWater == 0) {
        if (block_id1 < 1.5) {
            float k1;
            if (block_id0 > 0.5)
                k1 = fog(dist1, FOG_AIR_DECAY);
            else
                k1 = fog(FOG_THICKNESS, FOG_AIR_DECAY);
            float k2 = fog(dist0, FOG_AIR_DECAY);
            color = color * k1;
            translucent = translucent * k2;
            fog_scatter0 = k2 * (1 - k2) * fog_scatter0 + (1 - k2) * (1 - k2) * alpha * fog_color;
            fog_scatter1 = k1 * (1 - k1) * fog_scatter1 + (1 - k1) * (1 - k1) * fog_color;
            fog_decay0 = k2;
            fog_decay1 = k1;
        }
        if (block_id1 > 1.5) {
            float k1 = fog(dist1 - dist0, FOG_WATER_DECAY);
            color = color * k1;
            translucent = translucent * k1;
            vec3 water_color = LUT_water_scattering(fog_blend(1, lumi_data.y, k1)) * sky_brightness / SKY_ILLUMINATION_INTENSITY * lumi_data.w;
            fog_scatter0 = k1 * (1 - k1) * fog_scatter0 + (1 - k1) * (1 - k1) * alpha * water_color;
            fog_scatter1 = k1 * (1 - k1) * fog_scatter1 + (1 - k1) * (1 - k1) * water_color;
            float k2 = fog(dist0, FOG_AIR_DECAY);
            color = color * k2;
            translucent = translucent * k2;
            fog_scatter0 = k2 * (2 - k2) * fog_scatter0 + (1 - k2) * (1 - k2) * alpha * fog_color;
            fog_scatter1 = k2 * (2 - k2) * fog_scatter1 + (1 - k2) * (1 - k2) * fog_color;
            fog_decay0 = k1 * k2;
            fog_decay1 = k1 * k2;
        } 
    }
    else if (isEyeInWater == 1) {
        if (block_id1 < 1.5) {
            float k1 = fog(dist1, FOG_WATER_DECAY);
            float k2 = fog(dist0, FOG_WATER_DECAY);
            color = color * k1;
            translucent = translucent * k2;
            vec3 water_color0 = LUT_water_scattering(fog_blend(lumi_data.z, lumi_data.y, k2)) * sky_brightness / SKY_ILLUMINATION_INTENSITY * (0.5 * lumi_data.z + 0.5);
            vec3 water_color1 = LUT_water_scattering(fog_blend(lumi_data.z, lumi_data.y, k1)) * sky_brightness / SKY_ILLUMINATION_INTENSITY * (0.5 * lumi_data.z + 0.5);
            fog_scatter0 = k2 * (1 - k2) * fog_scatter0 + (1 - k2) * (1 - k2) * alpha * water_color0;
            fog_scatter1 = k1 * (1 - k1) * fog_scatter1 + (1 - k1) * (1 - k1) * water_color1;
            fog_decay0 = k2;
            fog_decay1 = k1;
        }
        if (block_id1 > 1.5) {
            float k1;
            if (block_id0 > 0.5) 
                k1 = fog(dist1 - dist0, FOG_AIR_DECAY);
            else
                k1 = fog(FOG_THICKNESS, FOG_AIR_DECAY);
            color = color * k1;
            translucent = translucent * k1;
            fog_scatter0 = k1 * (1 - k1) * fog_scatter0 + (1 - k1) * (1 - k1) * alpha * sky_color;
            fog_scatter1 = k1 * (1 - k1) * fog_scatter1 + (1 - k1) * (1 - k1) * sky_color;
            float k2 = fog(dist0, FOG_WATER_DECAY);
            color = color * k2;
            translucent = translucent * k2;
            vec3 water_color = LUT_water_scattering(fog_blend(lumi_data.z, lumi_data.w, k2)) * sky_brightness / SKY_ILLUMINATION_INTENSITY * (0.5 * lumi_data.z + 0.5);
            fog_scatter0 = k2 * (2 - k2) * fog_scatter0 + (1 - k2) * (1 - k2) * alpha * water_color;
            fog_scatter1 = k2 * (2 - k2) * fog_scatter1 + (1 - k2) * (1 - k2) * water_color;
            fog_decay0 = k1 * k2;
            fog_decay1 = k1 * k2;
        } 
    }

    /* BLOOM EXTRACT */
    vec3 bloom_color = color * (1 - alpha) * fog_decay1;
    bloom_color = pow(bloom_color, vec3(1 / GAMMA));
    if (block_id0 > 1.5) {
        bloom_color = mix(vec3(0.0), bloom_color, smoothstep(0.4, 0.6, grayscale(bloom_color)));
    }
    else {
        bloom_color = 0.5 * mix(vec3(0.0), bloom_color, smoothstep(1.5, 2, grayscale(bloom_color)));
    }

    gl_FragData[0] = vec4(color, 1.0);
    gl_FragData[1] = vec4(translucent, alpha);
    gl_FragData[2] = vec4(fog_scatter0, fog_decay0);
    gl_FragData[3] = vec4(fog_scatter1, fog_decay1);
    gl_FragData[4] = vec4(bloom_color, 1.0);
}