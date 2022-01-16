#version 120

#define PI 3.1415926535898

#define SHADOW_EPSILON 1e-1
#define SHADOW_INTENSITY 0.5
#define SHADOW_FISHEY_LENS_INTENSITY 0.85

#define LIGHT_MODE 0                        // 1 for classic, 0 for physical
#define LIGHT_COLOR vec3(1, 0.72, 0.45)     // 4400K
#define LIGHT_CLASSIC_INTENSITY 1.0
#define LIGHT_PHYSICAL_INTENSITY 1.0
#define LIGHT_PHYSICAL_CLOSEST 0.25

const int RGB16F = 0;
const int gnormalFormat = RGB16F;
const int R32F = 0;
const int gdepthFormat = R32F;
const int RG16F = 0;
const int gaux1Format = RG16F;
const int shadowMapResolution = 4096; 
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
    vec4 translucent = texture2D(composite, texcoord);
    vec4 data1 = texture2D(gaux1, texcoord);
    float block_id = data1.x;

    vec3 screen_coord = vec3(texcoord, depth0);
    vec3 view_coord = screen_coord_to_view_coord(screen_coord);
    float dist = length(view_coord) / far;

    /* BLOOM EXTRACT */
    vec3 bloom_color = vec3(0.0);
    if (block_id > 1.5) {
        bloom_color = mix(vec3(0.0), color, smoothstep(0.25, 0.5, grayscale(color)));
    }   

    /* SHADOW */
    float sky_light_shadow = 0.0;
    if (block_id > 0.5 && block_id < 1.5) {
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
        sky_light_shadow *= current_depth >= closest_depth ? 0 : 1;
        sky_light_shadow = SHADOW_INTENSITY * (1 - sky_light_shadow);
        sky_light_shadow *= shaodw_dist_weight;
    }

    /* LIGHT */
    if (block_id > 0.5) {
        float sun_angle = sunAngle < 0.5 ? 0.5 - 2 * abs(sunAngle - 0.25) : 0;
        vec3 sky_light = mix(vec3(0.1),
            vec3(
                1.5 * (exp(0.01 - 0.01 / (sin(PI * (0.05 + 0.95 * sun_angle))))),
                1.5 * (exp(0.1 - 0.1  / (sin(PI * (0.05 + 0.95 * sun_angle))))),
                1.5 * (exp(0.3 - 0.3  / (sin(PI * (0.05 + 0.95 * sun_angle)))))
            ), smoothstep(0, 0.02, sun_angle));

        #if LIGHT_MODE
            vec3 block_light = LIGHT_CLASSIC_INTENSITY * 1.0 * data1.y * LIGHT_COLOR;
        #else
            float block_light_dist = LIGHT_PHYSICAL_CLOSEST - log(clamp(1.07 * data1.y, 0, 1));
            vec3 block_light = LIGHT_PHYSICAL_INTENSITY * 0.25 / (block_light_dist * block_light_dist) * LIGHT_COLOR;
        #endif

        sky_light = sky_light * (1 - sky_light_shadow);
        color = color * sqrt(block_light * block_light + sky_light * sky_light);
    }

    /* TRANSLUCENT */
    color = color + translucent.rgb;
    
    gl_FragData[0] = vec4(color + 0.5 * bloom_color, 1.0);
    gl_FragData[1] = vec4(dist, 0.0, 0.0, 0.0);
    gl_FragData[2] = vec4(bloom_color, 1.0);
}