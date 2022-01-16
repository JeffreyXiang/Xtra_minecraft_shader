#version 120

uniform sampler2D gcolor;
uniform sampler2D depthtex0;

uniform float far;
uniform vec3 fogColor;
uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;

varying vec2 texcoord;

vec3 screen_coord_to_view_coord(vec3 screen_coord) {
    vec4 ndc_coord = vec4(screen_coord * 2 - 1, 1);
    vec4 clid_coord = gbufferProjectionInverse * ndc_coord;
    vec3 view_coord = clid_coord.xyz / clid_coord.w;
    return view_coord;
}

/* DRAWBUFFERS: 0 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).x;
    float dist = length(screen_coord_to_view_coord(vec3(texcoord, depth)));
    if (depth < 1)
    color = mix(color, fogColor, clamp(pow(dist / far, 4), 0, 1));
    gl_FragData[0] = vec4(color, 1.0);
}