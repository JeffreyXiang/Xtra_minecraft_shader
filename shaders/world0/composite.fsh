#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SHADOW_EPSILON 1e-1
#define SHADOW_INTENSITY 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SHADOW_FISHEY_LENS_INTENSITY 0.85

#define ILLUMINATION_EPSILON 0.5
#define ILLUMINATION_MODE 0 // [0 1]
#define BLOCK_ILLUMINATION_COLOR_TEMPERATURE 4400   // [2400 2800 3200 3600 4000 4400 4800 5200 5600 6000 6400 6800 7200]
#if BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 2400
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.3364, 0.0501)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 2800
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.4195, 0.1119)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 3200
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.4970, 0.1879)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 3600
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.5689, 0.2745)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 4000
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.6354, 0.3684)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 4400
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.6966, 0.4668)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 4800
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.7528, 0.5675)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 5200
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.8044, 0.6685)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 5600
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.8518, 0.7686)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 6000
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.8952, 0.8666)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 6400
    #define BLOCK_ILLUMINATION_COLOR vec3(1.0000, 0.9351, 0.9616)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 6800
    #define BLOCK_ILLUMINATION_COLOR vec3(0.9488, 0.9219, 1.0501)
#elif BLOCK_ILLUMINATION_COLOR_TEMPERATURE == 7200
    #define BLOCK_ILLUMINATION_COLOR vec3(0.8753, 0.8799, 1.0501)
#endif
#define BLOCK_ILLUMINATION_CLASSIC_INTENSITY 1.5    //[0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.25 2.5]
#define BLOCK_ILLUMINATION_PHYSICAL_INTENSITY 3.0   //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#define BLOCK_ILLUMINATION_PHYSICAL_CLOSEST 0.5    //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SKY_ILLUMINATION_INTENSITY 3.0  //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]

const int RGBA16F = 0;
const int gcolorFormat = RGBA16F;
const int RGB16F = 0;
const int gnormalFormat = RGB16F;
const int R32F = 0;
const int gdepthFormat = R32F;
const int gaux1Format = RGBA16F;
const int shadowMapResolution = 4096;   //[1024 2048 4096] 
const float	sunPathRotation	= -30.0;

uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux1;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadow;

uniform float far;
uniform vec3 shadowLightPosition;
uniform float sunAngle;

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

vec3 screen_coord_to_world_coord(vec3 screen_coord) {
    vec3 view_coord = screen_coord_to_view_coord(screen_coord);
    vec3 world_coord = view_coord_to_world_coord(view_coord);
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

float grayscale(vec3 color) {
    return color.r * 0.299 + color.g * 0.587 + color.b * 0.114;
}

/* DRAWBUFFERS: 013 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;
    float depth0 = texture2D(depthtex0, texcoord).x;
    float depth1 = texture2D(depthtex1, texcoord).x;
    vec3 normal = texture2D(gnormal, texcoord).xyz;
    vec3 translucent = texture2D(composite, texcoord).rgb;
    vec4 data1 = texture2D(gaux1, texcoord);
    float block_id = data1.x;

    vec3 screen_coord = vec3(texcoord, depth0);
    vec3 view_coord = screen_coord_to_view_coord(screen_coord);
    float dist = length(view_coord) / far;

    /* INVERSE GAMMA */
    color = pow(color, vec3(GAMMA));
    translucent = pow(translucent, vec3(GAMMA));

    /* SHADOW */
    float sky_light_shadow = 0.0;
    float in_shadow = 0.0;
    if (block_id > 0.5) {
        vec3 screen_coord = vec3(texcoord, depth1);
        vec3 view_coord = screen_coord_to_view_coord(screen_coord);
        view_coord += SHADOW_EPSILON * normal;
        vec3 world_coord = view_coord_to_world_coord(view_coord);
        vec3 light_direction = normalize(view_coord - 10 * shadowLightPosition);
        vec3 shadow_coord = world_coord_to_shadow_coord(world_coord);
        float shaodw_dist = length(world_coord) / far;
        float shaodw_dist_weight = 1 - smoothstep(0.6, 0.7, shaodw_dist);
        float current_depth = shadow_coord.z;
        float closest_depth = texture2D(shadow, fish_len_distortion(shadow_coord.xy * 2 - 1) * 0.5 + 0.5).x;
        sky_light_shadow = 1 - smoothstep(-0.05, 0.0, dot(light_direction, normal));
        in_shadow = current_depth >= closest_depth ? 1 : 0;
        sky_light_shadow *= 1 - in_shadow;
        sky_light_shadow = SHADOW_INTENSITY * (1 - sky_light_shadow);
        sky_light_shadow *= shaodw_dist_weight;
    }

    /* ILLUMINATION */
    float sun_angle = sunAngle < 0.5 ? 0.5 - 2 * abs(sunAngle - 0.25) : 0;
    vec3 sun_light = vec3(
        (exp(0.01 - 0.01 / (sin(PI * (0.05 + 0.95 * sun_angle))))),
        (exp(0.1 - 0.1  / (sin(PI * (0.05 + 0.95 * sun_angle))))),
        (exp(0.3 - 0.3  / (sin(PI * (0.05 + 0.95 * sun_angle)))))
    );
    vec3 moon_light = vec3(0.005);
    float sun_moon_mix = smoothstep(0, 0.02, sun_angle);
    vec3 sky_light = SKY_ILLUMINATION_INTENSITY * mix(moon_light, sun_light, sun_moon_mix);
    float sky_brightness = SKY_ILLUMINATION_INTENSITY * mix(0.005, 1, sun_moon_mix);

    if (block_id > 0.5) {
        #if ILLUMINATION_MODE
            vec3 block_light = BLOCK_ILLUMINATION_CLASSIC_INTENSITY * data1.y * BLOCK_ILLUMINATION_COLOR;
        #else
            float block_light_dist = block_id > 1.5 ? 0 : 13 - clamp(15 * data1.y - 1, 0, 13);
            block_light_dist = (1 - ILLUMINATION_EPSILON) * block_light_dist + ILLUMINATION_EPSILON * block_light_dist / (13 - block_light_dist) + BLOCK_ILLUMINATION_PHYSICAL_CLOSEST;
            vec3 block_light = BLOCK_ILLUMINATION_PHYSICAL_INTENSITY * BLOCK_ILLUMINATION_PHYSICAL_CLOSEST * BLOCK_ILLUMINATION_PHYSICAL_CLOSEST / (block_light_dist * block_light_dist) * BLOCK_ILLUMINATION_COLOR;
        #endif

        sky_light *= (in_shadow > 0.5 ? data1.z : 1) * (1 - sky_light_shadow);
        color *= block_light + sky_light;
    }
    else {
        color *= clamp(sky_brightness / 1.2, 1, 100);
    }

    /* BLOOM EXTRACT */
    vec3 bloom_color = pow(color, vec3(1 / GAMMA));
    if (block_id > 1.5) {
        bloom_color = 0.5 * mix(vec3(0.0), bloom_color, smoothstep(0.75, 1, grayscale(bloom_color)));
    }
    else {
        bloom_color = 0.5 * mix(vec3(0.0), bloom_color, smoothstep(10, 10, grayscale(bloom_color)));
    }

    /* TRANSLUCENT */
    color = color + translucent;
    
    gl_FragData[0] = vec4(color, 1.0);
    gl_FragData[1] = vec4(dist, 0.0, 0.0, 0.0);
    gl_FragData[2] = vec4(bloom_color, 1.0);
}