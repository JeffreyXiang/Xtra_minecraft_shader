#version 120

uniform sampler2D texture;
uniform sampler2D lightmap;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;

varying float blockId;

/* DRAWBUFFERS:02 */
void main() {
    // texture
    vec4 blockColor = texture2D(texture, texcoord.st);
    blockColor.rgb *= color;

    // light
    vec3 light = texture2D(lightmap, lightMapCoord.st).rgb; 
    blockColor.rgb *= light;

    gl_FragData[0] = blockColor;
    gl_FragData[1] = vec4(normal, 1.0);
}