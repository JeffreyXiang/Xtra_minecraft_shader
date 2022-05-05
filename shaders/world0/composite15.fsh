#version 120

uniform sampler2D gcolor;
uniform sampler2D gaux4;

varying vec2 texcoord;

/* RENDERTARGETS: 11 */
void main() {
    vec3 color_prev = texture2D(gcolor, texcoord).rgb;
    float dist_s_prev = texture2D(gaux4, texcoord).x;

    gl_FragData[0] = vec4(color_prev, dist_s_prev);
}