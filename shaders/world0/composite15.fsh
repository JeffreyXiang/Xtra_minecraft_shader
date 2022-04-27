#version 120

uniform sampler2D gdepth;
uniform sampler2D colortex11;

varying vec2 texcoord;

/* RENDERTARGETS: 11 */
void main() {
    float depth_s_prev = texture2D(gdepth, texcoord).x;
    vec3 prev_data = texture2D(colortex11, texcoord).rgb;

    gl_FragData[0] = vec4(prev_data, depth_s_prev);
}