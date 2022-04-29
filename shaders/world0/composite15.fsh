#version 120

uniform sampler2D gcolor;
uniform sampler2D gdepth;

varying vec2 texcoord;

/* RENDERTARGETS: 11 */
void main() {
    vec3 color_prev = texture2D(gcolor, texcoord).rgb;
    float depth_s_prev = texture2D(gdepth, texcoord).x;

    gl_FragData[0] = vec4(color_prev, depth_s_prev);
}