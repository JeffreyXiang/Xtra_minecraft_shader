#version 120

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform sampler2D gaux1;

uniform float viewWidth;
uniform float viewHeight;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;
varying float block_id;

/* DRAWBUFFERS:3467 */
void main() {
    vec4 blockColor = vec4(vec3(0.0), 0.1001);
    if (block_id < 1.5) {
        // texture
        blockColor = texture2D(texture, texcoord.st);
        blockColor.rgb *= color;

        // light
        vec3 light = texture2D(lightmap, lightMapCoord).rgb; 
        blockColor.rgb *= light;
    }

    gl_FragData[0] = blockColor;
    gl_FragData[1] = vec4(normal, 1.0);
    gl_FragData[2] = vec4(vec3(1.0), blockColor.a);
    gl_FragData[3] = vec4(block_id, lightMapCoord.t * 1.066667 - 0.03333333, 0.0, 1.0);
}