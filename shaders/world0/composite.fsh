#version 120

#define SHADOW_EPSILON 1e-1
#define SHADOW_STRENGTH 0.5
#define SHADOW_FISHEY_LENS_STRENGTH 0.85

const int RGB16F = 0;
const int gnormalFormat = RGB16F;
const int shadowMapResolution = 4096; 
const float	sunPathRotation	= -30.0;

uniform sampler2D texture;
uniform sampler2D depthtex0;
uniform sampler2D shadow;
uniform sampler2D gnormal;

uniform float far;
uniform vec3 shadowLightPosition;

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
    float distort = (1.0 - SHADOW_FISHEY_LENS_STRENGTH ) + dist * SHADOW_FISHEY_LENS_STRENGTH;
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


float get_shadow(vec3 screen_coord, vec3 normal) {
    vec3 view_coord = screen_coord_to_view_coord(screen_coord);
    view_coord += SHADOW_EPSILON * normal;
    vec3 world_coord = view_coord_to_world_coord(view_coord);
    vec3 light_direction = normalize(view_coord - 10 * shadowLightPosition);
    vec3 shadow_coord = world_coord_to_shadow_coord(world_coord);
    float dist = length(world_coord) / far;
    float dist_weight = 1 - smoothstep(0.6, 0.7, dist);
    float current_depth = shadow_coord.z;
    float closest_depth = texture2D(shadow, fish_len_distortion(shadow_coord.xy * 2 - 1) * 0.5 + 0.5).x;
    float shadow = 1 - smoothstep(-0.05, 0, dot(light_direction, normal));
    shadow *= (current_depth >= closest_depth)? 0 : 1;
    shadow = SHADOW_STRENGTH * (1 - shadow);
    shadow *= dist_weight;
    return shadow;
}


/* DRAWBUFFERS: 0 */
void main() {
    vec3 color = texture2D(texture, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).x;
    vec3 normal = texture2D(gnormal, texcoord).xyz;

    float shadow = get_shadow(vec3(texcoord, depth), normal);
    
    color = color * (1 - shadow);
    
    gl_FragData[0] = vec4(color, 1.0);
}