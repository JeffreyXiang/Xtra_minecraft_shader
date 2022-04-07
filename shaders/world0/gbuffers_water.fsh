#version 120

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform sampler2D gdepth;
uniform sampler2D gaux4;

uniform float viewWidth;
uniform float viewHeight;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;
varying float block_id;

/* DRAWBUFFERS:13457 */
void main() {
    vec4 blockColor = vec4(vec3(0.0), 0.1001);
    vec2 depth_t_data = texture2D(gdepth, vec2(gl_FragCoord.s / viewWidth, gl_FragCoord.t / viewHeight));
    vec2 lum_t_data = texture2D(gaux4, vec2(gl_FragCoord.s / viewWidth, gl_FragCoord.t / viewHeight));
    if (block_id < 1.5) {
        // texture
        blockColor = texture2D(texture, texcoord.st);
        blockColor.rgb *= color;

        // light
        vec3 light = texture2D(lightmap, lightMapCoord).rgb; 
        blockColor.rgb *= light;

        depth_t_data.y = gl_FragCoord.z;
        lum_t_data.y = lightMapCoord.t * 1.066667 - 0.03333333;
    }
    else {
        depth_t_data.x = gl_FragCoord.z;
        lum_t_data.x = lightMapCoord.t * 1.066667 - 0.03333333;
    }

    gl_FragData[0] = vec4(depth_t_data, 0.0, 1.0);
    gl_FragData[1] = blockColor;
    gl_FragData[2] = vec4(normal, block_id > 1.5 ? 1.0 : 0.0);
    gl_FragData[3] = vec4(normal, block_id < 1.5 ? 1.0 : 0.0);
    gl_FragData[4] = vec4(lum_t_data, 0.0, 1.0);
}