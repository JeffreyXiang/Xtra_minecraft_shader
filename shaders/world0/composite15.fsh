#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define MOTION_BLUR_ENABLE 1 // [0 1]
#define MOTION_BLUR_SAMPLE_NUM 17 // [3 5 9 17 33 65 129]

uniform sampler2D gcolor;
uniform sampler2D colortex12;

#if MOTION_BLUR_ENABLE
const bool gcolorMipmapEnabled = true;
#endif

uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

vec2 offset(vec2 ori) {
    return vec2(ori.x / viewWidth, ori.y / viewHeight);
}

/* RENDERTARGETS: 0 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;

    /* MOTION BLUR */
#if MOTION_BLUR_ENABLE
    vec4 motion_data = texture2D(colortex12, texcoord);
    vec2 texcoord_prev = motion_data.st;
    vec2 velocity = texcoord_prev - texcoord;
    int mb_half_sample_num = (MOTION_BLUR_SAMPLE_NUM - 1) / 2;
    float level = log(1 + max(abs(velocity.x) * viewWidth, abs(velocity.y) * viewHeight) / MOTION_BLUR_SAMPLE_NUM);
    for (int i = 0; i < mb_half_sample_num; i++) {
        color += texture2D(gcolor, texcoord + (float(i) / mb_half_sample_num / 2) * velocity, level).rgb;
        color += texture2D(gcolor, texcoord - (float(i) / mb_half_sample_num / 2) * velocity, level).rgb;
    }
    color /= MOTION_BLUR_SAMPLE_NUM;
#endif
    
    gl_FragData[0] = vec4(color, 1.0);
}