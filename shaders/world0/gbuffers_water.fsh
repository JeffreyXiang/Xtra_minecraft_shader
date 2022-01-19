#version 120

uniform sampler2D texture;
uniform sampler2D lightmap;

varying vec3 color;
varying vec2 texcoord;
varying vec2 lightMapCoord;

varying float block_id;

/* DRAWBUFFERS:03 */
void main() {
    // texture
    vec4 blockColor = texture2D(texture, texcoord.st);
    blockColor.rgb *= color;

    // light
    vec3 light = texture2D(lightmap, vec2(lightMapCoord.st)).rgb; 
    blockColor.rgb *= light;

    gl_FragData[1] = blockColor;
    gl_FragData[0] = vec4(vec3(0.0), blockColor.a);
}