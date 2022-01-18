#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

uniform sampler2D gcolor;
uniform sampler2D composite;

varying vec2 texcoord;

/* DRAWBUFFERS: 0 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;
    vec3 bloom = texture2D(composite, texcoord).rgb;

    /* BLOOM */
    color += bloom;

    /* GAMMA */
    color = pow(color, vec3(1 / GAMMA));
    gl_FragData[0] = vec4(color, 1.0);
}