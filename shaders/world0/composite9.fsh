#version 120

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux4;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;

uniform float far;

varying vec2 texcoord;

/* DRAWBUFFERS: 0 */
void main() {
    /* OUTPUT & DEBUG */
    vec3 color = texture2D(gcolor, texcoord).rgb;
    vec3 depth0 = vec3(texture2D(depthtex0, texcoord).x);
    vec3 depth1 = vec3(texture2D(depthtex1, texcoord).x);
    vec3 dist0 = vec3(texture2D(gdepth, texcoord).x / far);
    vec3 dist1 = vec3(texture2D(gdepth, texcoord).y / far);
    vec3 shadow_water_dist = vec3(texture2D(gdepth, texcoord).z / 100);
    vec3 shadow0 = vec3(texture2D(shadowtex0, texcoord).x);
    vec3 shadow1 = vec3(texture2D(shadowtex1, texcoord).x);
    vec3 normal0 = vec3(texture2D(gnormal, texcoord).xy, 0) * 0.5 + 0.5;
    vec3 normal1 = vec3(texture2D(gaux1, texcoord).xy, 0) * 0.5 + 0.5;
    vec3 block_id0 = vec3(texture2D(gnormal, texcoord).w * 0.5);
    vec3 block_id1 = vec3(texture2D(gaux1, texcoord).w * 0.5);
    vec3 block_light = vec3(texture2D(gaux2, texcoord).x);
    vec3 sky_light = vec3(texture2D(gaux2, texcoord).y);
    vec3 ao = vec3(texture2D(gaux2, texcoord).z);
    vec3 translucent_light = vec3(texture2D(gaux2, texcoord).w);
    vec3 translucent = vec3(texture2D(gaux4, texcoord).rgb);
    vec3 bloom = vec3(texture2D(composite, texcoord).rgb);
    gl_FragData[0] = vec4(color, 1.0);
}