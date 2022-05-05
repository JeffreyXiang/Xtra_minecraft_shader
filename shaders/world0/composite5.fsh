#version 120

#define PI 3.1415926535898

#define FILTER_KERNEL_STRIDE 4

#define SSAO_ENABLE 1 // [0 1]
#define SSGI_ENABLE 1 // [0 1]
#define GI_SPATIAL_FILTER_ENABLE 1 // [0 1]
#define GI_SPATIAL_FILTER_PASSES 3 // [1 2 3]
#define GI_SPATIAL_FILTER_SIGMA_Z 1.
#define GI_SPATIAL_FILTER_SIGMA_N 128.
#define GI_SPATIAL_FILTER_SIGMA_L 4.
#define GI_RES_SCALE 0.5   //[0.25 0.5 1]

uniform sampler2D gnormal;
uniform sampler2D gaux4;
uniform sampler2D colortex9;

uniform mat4 gbufferProjectionInverse;

uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

vec2 offset(vec2 ori) {
    return vec2(ori.x / viewWidth, ori.y / viewHeight);
}

vec3 screen_coord_to_view_coord(vec3 screen_coord) {
    vec4 ndc_coord = vec4(screen_coord * 2 - 1, 1);
    vec4 clip_coord = gbufferProjectionInverse * ndc_coord;
    vec3 view_coord = clip_coord.xyz / clip_coord.w;
    return view_coord;
}

const float kernel[] = float[](0.0625, 0.25, 0.375, 0.35, 0.0625);

/* RENDERTARGETS: 9 */
void main() {
    vec4 gi_data = texture2D(colortex9, texcoord);
#if (SSAO_ENABLE || SSGI_ENABLE) && GI_SPATIAL_FILTER_ENABLE && GI_SPATIAL_FILTER_PASSES > 2
    /* GI CROSS BILATERAL */
    vec2 ssao_texcoord = (texcoord - 0.5) / GI_RES_SCALE + 0.5;
    if (ssao_texcoord.x > 0 && ssao_texcoord.x < 1 && ssao_texcoord.y > 0 && ssao_texcoord.y < 1) {
        vec4 gi = vec4(0.0);
        float w_sum = 0.0, w, w_z = 1, w_n = 1, w_c = 1;
        float clip_z_c =  texture2D(gaux4, ssao_texcoord).w, clip_z_t;
        vec4 normal_s_data = texture2D(gnormal, ssao_texcoord);
        vec3 normal_s_c = normal_s_data.xyz, normal_s_t;
        float block_id_s_c = normal_s_data.w, block_id_s_t;
        vec2 dz = normal_s_c.xy / (dot(normal_s_c, normalize(screen_coord_to_view_coord(vec3(ssao_texcoord, 1)))) + 1e-3);
        if (block_id_s_c > 0.5) {
            for (int i = 0; i < 5; i++) {
                for (int j = 0; j < 5; j++) {
                    clip_z_t = texture2D(gaux4, ssao_texcoord + offset(FILTER_KERNEL_STRIDE * vec2(i - 2, j - 2)) / GI_RES_SCALE).w;
                    normal_s_data = texture2D(gnormal, ssao_texcoord + offset(FILTER_KERNEL_STRIDE * vec2(i - 2, j - 2)) / GI_RES_SCALE);
                    normal_s_t = normal_s_data.xyz;
                    block_id_s_t = normal_s_data.w;
                    if (block_id_s_t > 0.5) {
                        w_z = exp(
                            -(abs(clip_z_t - clip_z_c)) 
                            / 
                            (GI_SPATIAL_FILTER_SIGMA_Z * abs(clip_z_c / viewWidth / GI_RES_SCALE * 2 * dot(dz, FILTER_KERNEL_STRIDE * vec2(i - 2, j - 2))) + 1e-3)
                        );
                        w_n = pow(max(0.0, dot(normal_s_c, normal_s_t)), GI_SPATIAL_FILTER_SIGMA_N);
                        w = kernel[i] * kernel[j] * w_z * w_n * w_c;
                        gi += w * texture2D(colortex9, texcoord + offset(FILTER_KERNEL_STRIDE * vec2(i - 2, j - 2)));
                        w_sum += w;
                    }
                }
            }
        }
        gi_data = w_sum == 0 ? vec4(0.0) : gi / w_sum;
    }
#endif
    gl_FragData[0] = gi_data;
}