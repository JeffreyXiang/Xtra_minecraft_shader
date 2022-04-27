#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SSAO_ENABLE 1 // [0 1]
#define SSGI_ENABLE 1 // [0 1]

uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D colortex8;
uniform sampler2D colortex9;

varying vec2 texcoord;

/* RENDERTARGETS: 0 */
void main() {
    vec3 color_s = texture2D(gcolor, texcoord).rgb;
    float block_id_s = texture2D(gnormal, texcoord).a;
    vec4 gi_data = texture2D(colortex9, texcoord);

    /* APPPLY GI */
    if (block_id_s > 0.5) {
    #if SSAO_ENABLE
        color_s *= pow(gi_data.a, GAMMA);
    #endif
    #if SSGI_ENABLE
        vec3 albedo_s = texture2D(colortex8, texcoord).rgb;
        color_s += albedo_s * gi_data.rgb;
    #endif
    }

    gl_FragData[0] = vec4(color_s, 0.0);
}