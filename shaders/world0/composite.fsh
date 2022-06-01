#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SSAO_ENABLE 1 // [0 1]
#define SSGI_ENABLE 1 // [0 1]
#define GI_TEMPORAL_FILTER_ENABLE 1 // [0 1]
#define TAA_ENABLE 1 // [0 1]
#define MOTION_BLUR_ENABLE 1 // [0 1]

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D depthtex1;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D colortex15;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

const float Halton2[] = float[](1./2, 1./4, 3./4, 1./8, 5./8, 3./8, 7./8, 1./16);
const float Halton3[] = float[](1./3, 2./3, 1./9, 4./9, 7./9, 2./9, 5./9, 8./9);

varying vec2 texcoord;

vec3 screen_coord_to_view_coord(vec3 screen_coord) {
    vec4 ndc_coord = vec4(screen_coord * 2 - 1, 1);
    vec4 clip_coord = gbufferProjectionInverse * ndc_coord;
    vec3 view_coord = clip_coord.xyz / clip_coord.w;
    return view_coord;
}

vec3 view_coord_to_previous_view_coord(vec3 view_coord) {
    vec3 world_coord = (gbufferModelViewInverse * vec4(view_coord, 1.0)).xyz + cameraPosition;
    vec3 previous_view_coord = (gbufferPreviousModelView * vec4(world_coord - previousCameraPosition, 1.0)).xyz;
    return previous_view_coord;
}

vec3 previous_view_coord_to_previous_screen_coord(vec3 previous_view_coord) {
    vec4 previous_clip_coord = gbufferPreviousProjection * vec4(previous_view_coord, 1);
    vec3 previous_ndc_coord = previous_clip_coord.xyz / previous_clip_coord.w;
    vec3 previous_screen_coord = previous_ndc_coord * 0.5 + 0.5;
    return previous_screen_coord;
}

vec2 nearest(vec2 texcoord) {
    return vec2((floor(texcoord.s * viewWidth) + 0.5) / viewWidth, (floor(texcoord.t * viewHeight) + 0.5) / viewHeight);
}

vec2 offset(vec2 ori) {
    return vec2(ori.x / viewWidth, ori.y / viewHeight);
}

int is_dist_match(float dist, vec3 view_dir, vec3 normal_s, vec2 texcoord) {
    // int idx = int(mod(frameCounter, 8));
    // int idx_prev = int(mod(frameCounter-1, 8));
    // texcoord -= vec2((Halton2[idx] - 0.5) / viewWidth, (Halton3[idx] - 0.5) / viewHeight);
    // texcoord += vec2((Halton2[idx_prev] - 0.5) / viewWidth, (Halton3[idx_prev] - 0.5) / viewHeight);
    // texcoord = nearest(texcoord);
    float dist_prev = texture2D(colortex11, texcoord).a;
    float k = dot(view_dir, normal_s);
    k = 1 - sqrt(1 - k * k) / k;
    return (dist > dist_prev - 2e-3 * k * dist_prev && dist < dist_prev + 2e-3 * k * dist_prev) ? 1 : 0;
}

/* RENDERTARGETS: 0,1,3,6,7,8,12,15 */
void main() {
    vec3 color_s = texture2D(gcolor, texcoord).rgb;
    vec3 data_w = texture2D(gdepth, texcoord).rgb;
    float depth_w = data_w.x;
    float sky_light_w = data_w.y;
    float block_id_w = data_w.z - 1;
    vec4 normal_data_s = texture2D(gnormal, texcoord);
    vec3 normal_s = normal_data_s.rgb;
    float block_id_s = normal_data_s.a;
    float depth_s = texture2D(depthtex1, texcoord).x;
    vec4 color_data_g = texture2D(composite, texcoord);
    vec3 color_g = color_data_g.rgb;
    float alpha = color_data_g.a;
    vec2 lum_data_s = texture2D(gaux3, texcoord).xy;
    float block_light_s = lum_data_s.x;
    float sky_light_s = lum_data_s.y;
    vec3 data_g = texture2D(gaux4, texcoord).xyz;
    float depth_g = data_g.x;
    float sky_light_g = data_g.y;
    float block_id_g = data_g.z;

    float dist_s = 9999;
    float dist_w = 9999;
    float dist_g = 9999;
    float clip_z = 9999;

    vec3 screen_coord = vec3(texcoord, depth_s);
    vec3 view_coord = screen_coord_to_view_coord(screen_coord);
    if (block_id_s > 0.5) {
        dist_s = length(view_coord);
        clip_z = -view_coord.z;
    }
    else depth_s = 2;
    if (block_id_w > 0.5){
        vec3 screen_coord = vec3(texcoord, depth_w);
        vec3 view_coord_ = screen_coord_to_view_coord(screen_coord);
        dist_w = length(view_coord_);
    }
    else depth_w = 2;
    if (block_id_g > 0.5){
        vec3 screen_coord = vec3(texcoord, depth_g);
        vec3 view_coord_ = screen_coord_to_view_coord(screen_coord);
        dist_g = length(view_coord_);
    }
    else depth_g = 2;
    
    
    /* INVERSE GAMMA */
    color_s = pow(color_s, vec3(GAMMA));
    color_g = pow(color_g, vec3(GAMMA));

    /* LUTS */
    vec4 LUT_data = vec4(0.0);
    vec2 LUT_texcoord = vec2(texcoord.x / 256 * viewWidth, texcoord.y / 256 * viewHeight);
    if (LUT_texcoord.x < 1 && LUT_texcoord.y < 1)
        LUT_data = texture2D(colortex15, LUT_texcoord);

    /* MOTION */
    vec2 texcoord_prev = vec2(0.0);
    float has_prev = 0;
#if (SSAO_ENABLE || SSGI_ENABLE) && GI_TEMPORAL_FILTER_ENABLE || TAA_ENABLE || MOTION_BLUR_ENABLE
    if (fract(block_id_s + 1e-3) < 0.05) {
        vec4 motion_data = texture2D(colortex12, texcoord);
        vec3 motion = motion_data.xyz;
        float is_moving = motion_data.w;
        vec3 previous_view_coord = (is_moving == 1 ? view_coord - motion : view_coord_to_previous_view_coord(view_coord));
        float previous_dist_s = length(previous_view_coord);
        texcoord_prev = previous_view_coord_to_previous_screen_coord(previous_view_coord).st;
        if (texcoord_prev.s > 0 && texcoord_prev.s < 1 && texcoord_prev.t > 0 && texcoord_prev.t < 1 && is_dist_match(previous_dist_s, normalize(view_coord), normal_s, texcoord_prev) == 1) {
            has_prev = 1;
        }
    }
    else {
        texcoord_prev = texcoord;
        has_prev = 1;
    }
#endif
    
    gl_FragData[0] = vec4(color_s, 0.0);
    gl_FragData[1] = vec4(depth_s, depth_w, depth_g, 0.0);
    gl_FragData[2] = vec4(color_g, alpha);
    gl_FragData[3] = vec4(block_light_s, sky_light_s, sky_light_w, sky_light_g);
    gl_FragData[4] = vec4(dist_s, dist_w, dist_g, clip_z);
    gl_FragData[5] = vec4(color_s, 0.0);
    gl_FragData[6] = vec4(texcoord_prev, 0.0, has_prev);
    gl_FragData[7] = LUT_data;

}