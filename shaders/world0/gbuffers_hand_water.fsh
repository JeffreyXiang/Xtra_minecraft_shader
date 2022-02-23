#version 120

uniform sampler2D texture;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;

/* DRAWBUFFERS:367 */
void main() {
    // texture
    vec4 blockColor = texture2D(texture, texcoord.st);
    blockColor.rgb *= color;

    gl_FragData[0] = blockColor;
    gl_FragData[1] = vec4(vec3(1.0), blockColor.a);
    gl_FragData[2] = vec4(1, lightMapCoord.t * 1.066667 - 0.03333333, 0.0, 1.0);
}