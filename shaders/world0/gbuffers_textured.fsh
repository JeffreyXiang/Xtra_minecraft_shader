#version 120

uniform sampler2D texture;

varying vec3 color;
varying vec2 texcoord;

/* DRAWBUFFERS:0 */
void main() {
    // texture
    vec4 blockColor = texture2D(texture, texcoord.st);
    blockColor.rgb *= color;

    gl_FragData[0] = blockColor;
}