#version 120

uniform sampler2D texture;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;

/* DRAWBUFFERS:026 */
void main() {
    // texture
    vec4 blockColor = texture2D(texture, texcoord.st);
    blockColor.rgb *= color;

    gl_FragData[0] = blockColor;
    gl_FragData[1] = vec4(normal, (heldBlockLightValue > 0 || heldBlockLightValue2 > 0) ? 2.1 : 1.1);
    gl_FragData[2] = vec4(lightMapCoord.s * 1.066667 - 0.03333333, lightMapCoord.t * 1.066667 - 0.03333333, 0.0, 1.0);
}