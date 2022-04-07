/*
Buffer Usage

_s: solid
_w: water
-g: glass

----------------------------------------------------------------
 Idx |   Buffer      | C |     gbuffers     |   composite0-2   |
-----------------------------------------------------------------
     |               | r |                  |                  |
     |               |---|                  |                  |
     |               | g |     color_s      |     color_s      |
  0  |   gcolor      |---|                  |                  |
     |               | b |                  |                  |
     |               |------------------------------------------
     |               | a |                  |        ao        |
---------------------------------------------------------------------
     |               | r |  block_light_s   |      dist_s      |
     |               |-----------------------------------------------
     |               | g |   sky_light_s    |      dist_w      |
  1  |   gdepth      |---------------------------------------------
     |               | b |                  |      dist_g      |
     |               |-----------------------------------------------
     |               | a |                  |                  |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |---|                  |                  |
     |               | g |     normal_s     |     normal_s     |
  2  |   gnormal     |---|                  |                  |
     |               | b |                  |                  |
     |               |------------------------------------------
     |               | a |    block_id_s    |    block_id_s    |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |---|                  |                  |
     |               | g |     color_g      |     color_g      |
  3  |   composite   |---|                  |                  |
     |               | b |                  |                  |
     |               |------------------------------------------
     |               | a |      alpha       |      alpha       |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |----                  |                  |
     |               | g |     normal_w     |     normal_w     |
  4  |   gaux1       |----                  |                  |
     |               | b |                  |                  |
     |               |------------------------------------------
     |               | a |                  |     depth_w      |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |----                  |                  |
     |               | g |     normal_g     |     normal_g     |
  5  |   gaux2       |----                  |                  |
     |               | b |                  |                  |
     |               |------------------------------------------
     |               | a |                  |     depth_g      |
---------------------------------------------------------------------
     |               | r |                  |  block_light_s   |
     |               |---|     depth_w      |------------------------
     |               | g |                  |   sky_light_s    |
  6  |   gaux3       |---------------------------------------------
     |               | b |   sky_light_w    |   sky_light_w    |
     |               |-----------------------------------------------
     |               | a |                  |   sky_light_g    |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |---|     depth_g      |------------------------
     |               | g |                  |                  |
  7  |   gaux4       |---------------------------------------------
     |               | b |   sky_light_g    |                  |
     |               |-----------------------------------------------
     |               | a |                  |                  |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |-----------------------------------------------
     |               | g |                  |                  |
  8  |   colortex8   |---------------------------------------------
     |               | b |                  |                  |
     |               |-----------------------------------------------
     |               | a |                  |                  |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |-----------------------------------------------
     |               | g |                  |                  |
  9  |   colortex9   |---------------------------------------------
     |               | b |                  |                  |
     |               |-----------------------------------------------
     |               | a |                  |                  |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |-----------------------------------------------
     |               | g |                  |                  |
  10 |   colortex10  |---------------------------------------------
     |               | b |                  |                  |
     |               |-----------------------------------------------
     |               | a |                  |                  |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |-----------------------------------------------
     |               | g |                  |                  |
  11 |   colortex11  |---------------------------------------------
     |               | b |                  |                  |
     |               |-----------------------------------------------
     |               | a |                  |                  |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |-----------------------------------------------
     |               | g |                  |                  |
  12 |   colortex12  |---------------------------------------------
     |               | b |                  |                  |
     |               |-----------------------------------------------
     |               | a |                  |                  |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |-----------------------------------------------
     |               | g |                  |                  |
  13 |   colortex13  |---------------------------------------------
     |               | b |                  |                  |
     |               |-----------------------------------------------
     |               | a |                  |                  |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |-----------------------------------------------
     |               | g |                  |                  |
  14 |   colortex14  |---------------------------------------------
     |               | b |                  |                  |
     |               |-----------------------------------------------
     |               | a |                  |                  |
---------------------------------------------------------------------
     |               | r |                  |                  |
     |               |----------------------|                  |-----
     |               | g |                  |                  |
  15 |   colortex15  |----------------------|       LUT        |---
     |               | b |                  |                  |
     |               |----------------------|                  |-----
     |               | a |                  |                  |
---------------------------------------------------------------------
*/

#version 120

const int RGBA8F = 0;
const int RGBA16F = 0;
const int RGBA32F = 0;
const int RGB16F = 0;
const int gcolorFormat = RGBA16F;
const int gnormalFormat = RGBA16F;
const int gdepthFormat = RGBA32F;
const int compositeFormat = RGBA16F;
const int gaux1Format = RGBA16F;
const int gaux2Format = RGBA16F;
const int gaux3Format = RGBA16F;
const int gaux4Format = RGBA16F;
const int colortex8Format = RGBA16F;
const int colortex15Format = RGBA32F;
const int shadowMapResolution = 4096;   //[1024 2048 4096] 
const int noiseTextureResolution = 256;
const float	sunPathRotation	= -30.0;

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex15;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D noisetex;

uniform float far;

varying vec2 texcoord;

/* DRAWBUFFERS: 0 */
void main() {
    /* OUTPUT & DEBUG */
    vec3 color = texture2D(gcolor, texcoord).rgb;

    /* gbuffers */
    // vec3 color_s = vec3(texture2D(gcolor, texcoord).rgb);
    // vec3 block_light_s = vec3(texture2D(gdepth, texcoord).x);
    // vec3 sky_light_s = vec3(texture2D(gdepth, texcoord).y);
    // vec3 normal_s = vec3(texture2D(gnormal, texcoord).rgb * 0.5 + 0.5);
    // vec3 block_id_s = vec3(texture2D(gnormal, texcoord).a / 2);
    // vec3 color_g = vec3(texture2D(composite, texcoord).rgb);
    // vec3 alpha = vec3(texture2D(composite, texcoord).a);
    // vec3 normal_w = vec3(texture2D(gaux1, texcoord).rgb * 0.5 + 0.5);
    // vec3 normal_g = vec3(texture2D(gaux2, texcoord).rgb * 0.5 + 0.5);
    // vec3 depth_w = vec3(texture2D(gaux3, texcoord).x);
    // vec3 sky_light_w = vec3(texture2D(gaux3, texcoord).y);
    // vec3 depth_g = vec3(texture2D(gaux4, texcoord).x);
    // vec3 sky_light_g = vec3(texture2D(gaux4, texcoord).y);

    /* composite0-2 */
    vec3 color_s = vec3(texture2D(gcolor, texcoord).rgb);
    vec3 ao = vec3(texture2D(gcolor, texcoord).a);
    vec3 dist_s = vec3(texture2D(gdepth, texcoord).x / far);
    vec3 dist_w = vec3(texture2D(gdepth, texcoord).y / far);
    vec3 dist_g = vec3(texture2D(gdepth, texcoord).z / far);
    vec3 normal_s = vec3(texture2D(gnormal, texcoord).rgb * 0.5 + 0.5);
    vec3 block_id_s = vec3(texture2D(gnormal, texcoord).a / 2);
    vec3 color_g = vec3(texture2D(composite, texcoord).rgb);
    vec3 alpha = vec3(texture2D(composite, texcoord).a);
    vec3 normal_w = vec3(texture2D(gaux1, texcoord).rgb * 0.5 + 0.5);
    vec3 depth_w = vec3(texture2D(gaux1, texcoord).a);
    vec3 normal_g = vec3(texture2D(gaux2, texcoord).rgb * 0.5 + 0.5);
    vec3 depth_g = vec3(texture2D(gaux2, texcoord).a);
    vec3 block_light_s = vec3(texture2D(gaux3, texcoord).x);
    vec3 sky_light_s = vec3(texture2D(gaux3, texcoord).y);
    vec3 sky_light_w = vec3(texture2D(gaux3, texcoord).z);
    vec3 sky_light_g = vec3(texture2D(gaux3, texcoord).w);
    vec3 lut_data = vec3(texture2D(colortex15, texcoord).rgb);


    // vec3 depth0 = vec3(texture2D(depthtex0, texcoord).x);
    // vec3 depth1 = vec3(texture2D(depthtex1, texcoord).x);
    // vec3 dist0 = vec3(texture2D(gdepth, texcoord).x / far);
    // vec3 dist1 = vec3(texture2D(gdepth, texcoord).y / far);
    // vec3 k0 = vec3(texture2D(gdepth, texcoord).z);
    // vec3 k1 = vec3(texture2D(gdepth, texcoord).w);
    // vec3 translucent = vec3(texture2D(composite, texcoord).rgb);
    // vec3 alpha = vec3(texture2D(composite, texcoord).a);
    // vec3 shadow0 = vec3(texture2D(shadowtex0, texcoord).x);
    // vec3 shadow1 = vec3(texture2D(shadowtex1, texcoord).x);
    // vec3 normal0 = vec3(texture2D(gnormal, texcoord).xy, 0) * 0.5 + 0.5;
    // vec3 normal1 = vec3(texture2D(gaux1, texcoord).xy, 0) * 0.5 + 0.5;
    // vec3 block_id0 = vec3(texture2D(gnormal, texcoord).w * 0.5);
    // vec3 block_id1 = vec3(texture2D(gaux1, texcoord).w * 0.5);
    // vec3 block_light = vec3(texture2D(gaux2, texcoord).x);
    // vec3 sky_light = vec3(texture2D(gaux2, texcoord).y);
    // vec3 ao = vec3(texture2D(gaux2, texcoord).z);
    // vec3 translucent_light = vec3(texture2D(gaux2, texcoord).w);
    // vec3 fog_decay0 = vec3(texture2D(gaux3, texcoord).a);
    // vec3 fog_decay1 = vec3(texture2D(gaux4, texcoord).a);
    // vec3 fog_scatter0 = vec3(texture2D(gaux3, texcoord).rgb);
    // vec3 fog_scatter1 = vec3(texture2D(gaux4, texcoord).rgb * fog_decay1);
    // vec3 bloom = vec3(texture2D(colortex8, texcoord).rgb);
    // vec3 texture_color = texture2D(colortex15, texcoord).rgb;
    // vec3 noise = texture2D(noisetex, texcoord).rgb;

    gl_FragData[0] = vec4(ao, 1.0);
}