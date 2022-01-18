#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

uniform sampler2D texture;
uniform sampler2D lightmap;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;

varying float block_id;

/* DRAWBUFFERS:024 */
void main() {
    // texture
    vec4 blockColor = texture2D(texture, texcoord.st);
    blockColor.rgb *= color;

    blockColor.rgb = pow(blockColor.rgb, vec3(GAMMA));

    gl_FragData[0] = blockColor;
    gl_FragData[1] = vec4(normal, 1.0);
    gl_FragData[2] = vec4(block_id, lightMapCoord.s, lightMapCoord.t, 1.0);
}