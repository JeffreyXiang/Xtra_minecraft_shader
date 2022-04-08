#version 120

uniform sampler2D texture;

uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform float viewWidth;
uniform float viewHeight;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;

/* DRAWBUFFERS:357 */
void main() {
    // texture
    vec4 blockColor = texture2D(texture, texcoord.st);
    blockColor.rgb *= color;

    gl_FragData[0] = blockColor;
    gl_FragData[1] = vec4(normal, 1.0);
    gl_FragData[2] = vec4(gl_FragCoord.z, lightMapCoord.t * 1.066667 - 0.03333333, 1.0, 1.0);
}