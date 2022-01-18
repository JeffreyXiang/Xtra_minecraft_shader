#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

uniform sampler2D texture;

varying vec3 color;
varying vec2 texcoord;

/* DRAWBUFFERS:0 */
void main() {
    // texture
    vec4 blockColor = texture2D(texture, texcoord.st);
    blockColor.rgb *= color;

    blockColor.rgb = pow(blockColor.rgb, vec3(GAMMA));

    gl_FragData[0] = blockColor;
}