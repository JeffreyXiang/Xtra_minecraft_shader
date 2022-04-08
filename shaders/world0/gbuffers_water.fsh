#version 120

uniform sampler2D texture;
uniform sampler2D lightmap;

uniform float viewWidth;
uniform float viewHeight;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;
varying float block_id;

/* DRAWBUFFERS:13457 */
void main() {
    vec4 blockColor = vec4(0.0);
    if (block_id < 1.5) {
        // texture
        blockColor = texture2D(texture, texcoord.st);
        blockColor.rgb *= color;

        // light
        vec3 light = texture2D(lightmap, lightMapCoord).rgb; 
        blockColor.rgb *= light;
    }


    vec3 data = vec3(gl_FragCoord.z, lightMapCoord.t * 1.066667 - 0.03333333, block_id);

    gl_FragData[1] = blockColor;
    gl_FragData[2] = vec4(normal, block_id > 1.5 ? 1.0 : 0.0);
    gl_FragData[3] = vec4(normal, block_id < 1.5 ? 1.0 : 0.0);
    gl_FragData[0] = vec4(data, block_id > 1.5 ? 1.0 : 0.0);
    gl_FragData[4] = vec4(data, block_id < 1.5 ? 1.0 : 0.0);
}