#version 120

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D depthtex0;

uniform float far;
uniform vec3 fogColor;
uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;

varying vec2 texcoord;

/* DRAWBUFFERS: 0 */
void main() {
    /* FOG */
    vec3 color = texture2D(gcolor, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).x;
    float dist = texture2D(gdepth, texcoord).x;
    if (depth < 1)
        color = mix(color, fogColor, clamp(pow(dist, 4), 0, 1));
    gl_FragData[0] = vec4(color, 1.0);
}