#version 120


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

    gl_FragData[0] = blockColor;
    gl_FragData[1] = vec4(normal, 1.0);
    gl_FragData[2] = vec4(block_id, lightMapCoord.s, lightMapCoord.t, 1.0);
}