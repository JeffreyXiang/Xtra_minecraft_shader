/*
Buffer Usage

_s: solid
_w: water
-g: glass

----------------------------------------------------------------------------------------------------------------
 Idx |   Buffer      |  dtype  | C |     gbuffers     |   composite0-3   |   composite4-    |   composite4-    |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |---|                  |                  |                  |                  |
     |               |         | g |     color_s      |     color_s      |     color_s      |     color_s      |
  0  |   gcolor      | RGBA16F |---|                  |                  |                  |                  |
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |                  |                  |                  |                  |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |     depth_w      |     depth_s      |     depth_s      |     depth_s      |
     |               |         |--------------------------------------------------------------------------------
     |               |         | g |  block_light_w   |     depth_w      |     depth_w      |     depth_w      |
  1  |   gdepth      | RGBA32F |--------------------------------------------------------------------------------
     |               |         | b |   sky_light_w    |     depth_g      |     depth_g      |     depth_g      |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |                  |                  |                  |                  |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |---|                  |                  |                  |                  |
     |               |         | g |     normal_s     |     normal_s     |     normal_s     |     normal_s     |
  2  |   gnormal     | RGBA16F |---|                  |                  |                  |                  |
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |    block_id_s    |    block_id_s    |    block_id_s    |    block_id_s    |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |---|                  |                  |                  |                  |
     |               |         | g |     color_g      |     color_g      |     color_g      |     color_g      |
  3  |   composite   | RGBA16F |---|                  |                  |                  |                  |
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |      alpha       |      alpha       |      alpha       |      alpha       |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |----                  |                  |                  |                  |
     |               |         | g |     normal_w     |     normal_w     |     normal_w     |     normal_w     |
  4  |   gaux1       | RGBA16F |----                  |                  |                  |                  |
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |                  |   sky_light_w    |   sky_light_w    |   sky_light_w    |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |----                  |                  |                  |                  |
     |               |         | g |     normal_g     |     normal_g     |     normal_g     |     normal_g     |
  5  |   gaux2       | RGBA16F |----                  |                  |                  |                  |
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |                  |   sky_light_g    |   sky_light_g    |   sky_light_g    |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |  block_light_s   |  block_light_s   |  block_light_s   |  block_light_s   |
     |               |         |---|------------------|---------------------------------------------------------
     |               |         | g |   sky_light_s    |   sky_light_s    |   sky_light_s    |   sky_light_s    |
  6  |   gaux3       | RGBA16F |--------------------------------------------------------------------------------
     |               |         | b |                  |  block_light_w   |  block_light_w   |  block_light_w   |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |                  |  block_light_g   |  block_light_g   |  block_light_g   |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |     depth_g      |      dist_s      |      dist_s      |      dist_s      |
     |               |         |--------------------------------------------------------------------------------
     |               |         | g |  block_light_g   |      dist_w      |      dist_w      |      dist_w      |
  7  |   gaux4       | RGBA32F |--------------------------------------------------------------------------------
     |               |         | b |   sky_light_g    |      dist_g      |      dist_g      |      dist_g      |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |                  |                  |      clip_z      |      clip_z      |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |----------------------|                  |                  |                  |
     |               |         | g |                  |     albedo_s     |      bloom       |      bloom       |
  8  |   colortex8   | RGBA16F |----------------------|                  |                  |                  |
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |                  |                  |                  |                  |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |----------------------|                  |                  |                  |
     |               |         | g |                  |        gi        |        gi        |        gi        |
  9  |   colortex9   | RGBA16F |----------------------|                  |                  |                  |
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |                  |        ao        |        ao        |        ao        |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |---|                  |                  |                  |                  |
     |               |         | g |     gi_prev      |     gi_prev      |     gi_prev      |     gi_prev      |
  10 |   colortex10  | RGBA16F |---|                  |                  |                  |                  |
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |     ao_prev      |     ao_prev      |     ao_prev      |     ao_prev      |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |---|                  |                  |                  |                  |
     |               |         | g |    color_prev    |    color_prev    |    color_prev    |    color_prev    |
  11 |   colortex11  | RGBA16F |---|                  |                  |                  |                  |
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |   dist_s_prev    |   dist_s_prev    |   dist_s_prev    |   dist_s_prev    |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |---|                  |  texcoord_prev   |  texcoord_prev   |  texcoord_prev   |
     |               |         | g |      motion      |                  |                  |                  |
  12 |   colortex12  | RGBA32F |---|                  |---------------------------------------------------------
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |    is_moving     |     has_prev     |     has_prev     |     has_prev     |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | g |                  |                  |                  |                  |
  13 |   colortex13  | RGBA16F |--------------------------------------------------------------------------------
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |                  |                  |                  |                  |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | g |                  |                  |                  |                  |
  14 |   colortex14  | RGBA16F |--------------------------------------------------------------------------------
     |               |         | b |                  |                  |                  |                  |
     |               |         |--------------------------------------------------------------------------------
     |               |         | a |                  |                  |                  |                  |
----------------------------------------------------------------------------------------------------------------
     |               |         | r |                  |                  |                  |                  |
     |               |         |----------------------|                  |                  |                  |
     |               |         | g |                  |                  |                  |                  |
  15 |   colortex15  | RGBA32F |----------------------|       LUT        |       LUT        |       LUT        |
     |               |         | b |                  |                  |                  |                  |
     |               |         |----------------------|                  |                  |                  |
     |               |         | a |                  |                  |                  |                  |
----------------------------------------------------------------------------------------------------------------
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
const int gaux4Format = RGBA32F;
const int colortex8Format = RGBA16F;
const int colortex9Format = RGBA16F;
const int colortex10Format = RGBA16F;
const int colortex11Format = RGBA16F;
const int colortex12Format = RGBA32F;
const int colortex15Format = RGBA32F;
const bool colortex10Clear = false;
const bool colortex11Clear = false;
const int shadowMapResolution = 4096;   //[1024 2048 4096]
const bool shadowHardwareFiltering1 = true; 
const int noiseTextureResolution = 256;
const float	sunPathRotation	= -30.0;
const float ambientOcclusionLevel = 0.0;   //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

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
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D colortex15;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D noisetex;

uniform float far;

varying vec2 texcoord;

/* RENDERTARGETS: 0 */
void main() {
    /* OUTPUT & DEBUG */
    vec3 color = texture2D(gcolor, texcoord).rgb;

    /* gbuffers */
    // vec3 color_s = vec3(texture2D(gcolor, texcoord).rgb);
    // vec3 depth_w = vec3(texture2D(gdepth, texcoord).x);
    // vec3 sky_light_w = vec3(texture2D(gdepth, texcoord).y);
    // vec3 block_id_w = vec3(texture2D(gdepth, texcoord).z / 2);
    // vec3 normal_s = vec3(texture2D(gnormal, texcoord).rgb * 0.5 + 0.5);
    // vec3 block_id_s = vec3(texture2D(gnormal, texcoord).a / 2);
    // vec3 color_g = vec3(texture2D(composite, texcoord).rgb);
    // vec3 alpha = vec3(texture2D(composite, texcoord).a);
    // vec3 normal_w = vec3(texture2D(gaux1, texcoord).rgb * 0.5 + 0.5);
    // vec3 normal_g = vec3(texture2D(gaux2, texcoord).rgb * 0.5 + 0.5);
    // vec3 block_light_s = vec3(texture2D(gaux3, texcoord).x);
    // vec3 sky_light_s = vec3(texture2D(gaux3, texcoord).y);
    // vec3 depth_g = vec3(texture2D(gaux4, texcoord).a);
    // vec3 sky_light_g = vec3(texture2D(gaux4, texcoord).y);
    // vec3 block_id_g = vec3(texture2D(gaux4, texcoord).z);
   //  vec3 motion = vec3(texture2D(colortex12, texcoord).rgb * 10 + 0.5);
   //  vec3 is_moving = vec3(texture2D(colortex12, texcoord).a);

    /* composite0-3 */
    vec3 color_s = vec3(texture2D(gcolor, texcoord).rgb);
    vec3 gi = vec3(texture2D(colortex9, texcoord).rgb);
    vec3 ao = vec3(texture2D(colortex9, texcoord).a);
    vec3 gi_prev = vec3(texture2D(colortex10, texcoord).rgb);
    vec3 ao_prev = vec3(texture2D(colortex10, texcoord).a);
    vec3 depth_s = vec3(texture2D(gdepth, texcoord).x / 2);
    vec3 depth_w = vec3(texture2D(gdepth, texcoord).y / 2);
    vec3 depth_g = vec3(texture2D(gdepth, texcoord).z / 2);
    vec3 normal_s = vec3(texture2D(gnormal, texcoord).rgb * 0.5 + 0.5);
    vec3 block_id_s = vec3(texture2D(gnormal, texcoord).a / 2);
    vec3 color_g = vec3(texture2D(composite, texcoord).rgb);
    vec3 alpha = vec3(texture2D(composite, texcoord).a);
    vec3 normal_w = vec3(texture2D(gaux1, texcoord).rgb * 0.5 + 0.5);
    vec3 sky_light_w = vec3(texture2D(gaux1, texcoord).a);
    vec3 normal_g = vec3(texture2D(gaux2, texcoord).rgb * 0.5 + 0.5);
    vec3 sky_light_g = vec3(texture2D(gaux2, texcoord).a);
    vec3 block_light_s = vec3(texture2D(gaux3, texcoord).x);
    vec3 sky_light_s = vec3(texture2D(gaux3, texcoord).y);
    vec3 block_light_w = vec3(texture2D(gaux3, texcoord).z);
    vec3 block_light_g = vec3(texture2D(gaux3, texcoord).w);
    vec3 dist_s = vec3(texture2D(gaux4, texcoord).x / far);
    vec3 dist_w = vec3(texture2D(gaux4, texcoord).y / far);
    vec3 dist_g = vec3(texture2D(gaux4, texcoord).z / far);
    vec3 texcoord_prev = vec3(texture2D(colortex12, texcoord).rgb);
    vec3 has_prev = vec3(texture2D(colortex12, texcoord).a);
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

    gl_FragData[0] = vec4(color, 1.0);
}