#version 120

uniform sampler2D gcolor;
uniform sampler2D depthtex0;
uniform sampler2D shadow;
uniform sampler2D gnormal;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjection;

varying vec2 texcoord;

/* DRAWBUFFERS: 0 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;
    vec3 depth = vec3(texture2D(depthtex0, texcoord).x);
    vec3 shadow = vec3(texture2D(shadow, texcoord).x);
    vec3 normal = vec3(texture2D(gnormal, texcoord).xy, 0) * 0.5 + 0.5;
    gl_FragData[0] = vec4(color, 1.0);
}