#version 120

#define BLOOM_ENABLE 1 // [0 1]

#define DOF_ENABLE 1 // [0 1]
#define DOF_INTENSITY 10 // [1 2 5 10 15 20 25 30 35 40 45 50 100]
#define DOF_MAX_RADIUS 8
#define DOF_STEP 3

uniform sampler2D gcolor;
uniform sampler2D composite;
uniform sampler2D gaux4;
uniform sampler2D colortex8;

#if DOF_ENABLE
const bool gcolorMipmapEnabled = true;
const bool compositeMipmapEnabled = true;
const bool gaux4MipmapEnabled = true;
#endif
#if BLOOM_ENABLE
const bool colortex8MipmapEnabled = true;
#endif

uniform float centerDepthSmooth;

uniform mat4 gbufferProjectionInverse;

varying vec2 texcoord;

vec3 screen_coord_to_view_coord(vec3 screen_coord) {
    vec4 ndc_coord = vec4(screen_coord * 2 - 1, 1);
    vec4 clip_coord = gbufferProjectionInverse * ndc_coord;
    vec3 view_coord = clip_coord.xyz / clip_coord.w;
    return view_coord;
}

/* RENDERTARGETS: 2,3,5,8 */
void main() {
    #if BLOOM_ENABLE || DOF_ENABLE
    vec4 color_g = texture2D(composite, texcoord);
    vec4 bloom_color = vec4(0.0);
    vec4 dof_color = vec4(0.0);
    vec4 dof_color_g = vec4(0.0);
    vec2 tex_coord;
    float s = 1;
    #if DOF_ENABLE
        float center_depth_smooth = -screen_coord_to_view_coord(vec3(0.5, 0.5, centerDepthSmooth)).z;
        float dist_g = texture2D(gaux4, texcoord).z;
        float dof_radius_g = dist_g < center_depth_smooth ? min(DOF_MAX_RADIUS, DOF_INTENSITY / center_depth_smooth * abs(dist_g - center_depth_smooth) / dist_g) : 0;
        color_g *= min(1, max(0, DOF_STEP * 2 - dof_radius_g) / DOF_STEP);
        tex_coord = (texcoord - vec2(0, 0.75)) * 4;
        if (tex_coord.s > 0 && tex_coord.s < 1 && tex_coord.t > 0 && tex_coord.t < 1)
            dof_color_g.a = texture2D(composite, tex_coord).a;
        else
    #endif
    for (int i = 2; i < 5; i++) {
        tex_coord = texcoord - vec2(1 - s, mod(i, 2) == 0 ? 0 : 0.75);
        s *= 0.5;
        if (tex_coord.s > 0 && tex_coord.s < s && tex_coord.t > 0 && tex_coord.t < s) {
            #if DOF_ENABLE
                vec4 dist_data = texture2D(gaux4, tex_coord / s);
                float dist = dist_data.x;
                float dist_g = dist_data.z;
                float dof_radius = dist < center_depth_smooth ? min(DOF_MAX_RADIUS, DOF_INTENSITY / center_depth_smooth * abs(dist - center_depth_smooth) / dist) : 0,
                    dof_radius_g = dist_g < center_depth_smooth ? min(DOF_MAX_RADIUS, DOF_INTENSITY / center_depth_smooth * abs(dist_g - center_depth_smooth) / dist_g) : 0;
                float k = min(1, max(0, dof_radius - DOF_STEP * (i - 1)) / DOF_STEP);
                float k_g = min(1, max(0, dof_radius_g - DOF_STEP * (i - 1)) / DOF_STEP) * min(1, max(0, DOF_STEP * (i + 1) - dof_radius_g) / DOF_STEP);
                dof_color.rgb = texture2D(gcolor, tex_coord / s).rgb;
                dof_color.a = k;
                dof_color_g = texture2D(composite, tex_coord / s) * k_g;
            #endif
            #if BLOOM_ENABLE
                bloom_color = texture2D(colortex8, tex_coord / s);
            #endif
            break;
        }
        if (tex_coord.s < s) break;
    }
    
    gl_FragData[0] = dof_color;
    gl_FragData[1] = color_g;
    gl_FragData[2] = dof_color_g;
    gl_FragData[3] = bloom_color;
    #endif
}