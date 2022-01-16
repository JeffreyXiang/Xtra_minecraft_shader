#version 120

uniform sampler2D gcolor;
uniform sampler2D composite;

varying vec2 texcoord;

/* DRAWBUFFERS: 0 */
void main() {
    /* BLOOM */
    vec3 color = texture2D(gcolor, texcoord).rgb;
    vec3 bloom = texture2D(composite, texcoord).rgb;
    gl_FragData[0] = vec4(color + bloom, 1.0);
}