#version 120

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux1;
uniform sampler2D gaux4;
uniform sampler2D depthtex0;
uniform sampler2D shadow;

varying vec2 texcoord;

/* DRAWBUFFERS: 0 */
void main() {
    /* OUTPUT & DEBUG */
    vec3 color = texture2D(gcolor, texcoord).rgb;
    vec3 depth = vec3(texture2D(depthtex0, texcoord).x);
    vec3 dist = vec3(texture2D(gdepth, texcoord).x);
    vec3 shadow = vec3(texture2D(shadow, texcoord).x);
    vec3 normal = vec3(texture2D(gnormal, texcoord).xy, 0) * 0.5 + 0.5;
    vec3 block_id = vec3(texture2D(gaux1, texcoord).x * 0.5);
    vec3 block_light = vec3(texture2D(gaux1, texcoord).y);
    vec3 translucent = vec3(texture2D(gaux4, texcoord).rgb);
    vec3 bloom = vec3(texture2D(composite, texcoord).rgb);
    gl_FragData[0] = vec4(color, 1.0);
}