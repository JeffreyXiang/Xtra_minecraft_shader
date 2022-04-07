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

vec2 pack_depth(float depth) {
    float low = fract(1024 * depth);
    float high = depth - low / 1024;
    return vec2(high, low);
}

/* DRAWBUFFERS:357 */
void main() {
    // texture
    vec4 blockColor = texture2D(texture, texcoord.st);
    blockColor.rgb *= color;

    gl_FragData[0] = blockColor;
    gl_FragData[1] = vec4(normal, 1.0);
    gl_FragData[2] = vec4(pack_depth(gl_FragCoord.z), lightMapCoord.t * 1.066667 - 0.03333333, 1.0);
}