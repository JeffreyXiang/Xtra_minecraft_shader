#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D depthtex1;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D colortex15;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

vec3 screen_coord_to_view_coord(vec3 screen_coord) {
    vec4 ndc_coord = vec4(screen_coord * 2 - 1, 1);
    vec4 clid_coord = gbufferProjectionInverse * ndc_coord;
    vec3 view_coord = clid_coord.xyz / clid_coord.w;
    return view_coord;
}

/* RENDERTARGETS: 0,1,3,6,7,8,15 */
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

    if (block_id_s > 0.5) {
        vec3 screen_coord = vec3(texcoord, depth_s);
        vec3 view_coord_ = screen_coord_to_view_coord(screen_coord);
        dist_s = length(view_coord_);
        clip_z = -view_coord_.z;
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
    
    gl_FragData[0] = vec4(color_s, 0.0);
    gl_FragData[1] = vec4(depth_s, depth_w, depth_g, 0.0);
    gl_FragData[2] = vec4(color_g, alpha);
    gl_FragData[3] = vec4(block_light_s, sky_light_s, sky_light_w, sky_light_g);
    gl_FragData[4] = vec4(dist_s, dist_w, dist_g, clip_z);
    gl_FragData[5] = vec4(color_s, 0.0);
    gl_FragData[6] = LUT_data;

}