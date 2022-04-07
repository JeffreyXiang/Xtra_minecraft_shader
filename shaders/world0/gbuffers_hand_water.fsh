#version 120

uniform sampler2D texture;
uniform sampler2D gdepth;
uniform sampler2D gaux4;

uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform float viewWidth;
uniform float viewHeight;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;

/* DRAWBUFFERS:137 */
void main() {
    // texture
    vec4 blockColor = texture2D(texture, texcoord.st);
    blockColor.rgb *= color;

    vec2 depth_t_data = texture2D(gdepth, vec2(gl_FragCoord.s / viewWidth, gl_FragCoord.t / viewHeight));
    vec2 lum_t_data = texture2D(gaux4, vec2(gl_FragCoord.s / viewWidth, gl_FragCoord.t / viewHeight));
    depth_t_data.y = gl_FragCoord.z;
    lum_t_data.y = lightMapCoord.t * 1.066667 - 0.03333333;

    gl_FragData[0] = vec4(depth_t_data, 0.0, 1.0);
    gl_FragData[1] = blockColor;
    gl_FragData[2] = vec4(lum_t_data, 0.0, 1.0);
}