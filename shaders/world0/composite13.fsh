#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define MOON_INTENSITY 2.533e-6
#define SUN_SRAD 2.101e4
#define MOON_SRAD 2.101e4

#define SKY_ILLUMINATION_INTENSITY 20.0  //[5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]

#define EXPOSURE 1.0 //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define AUTO_EXPOSURE_ENABLE 1 // [0 1]
#define TONEMAP_ENABLE 1 // [0 1]
#define TONE_R 1.0 //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define TONE_G 1.0 //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define TONE_B 1.0 //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

uniform sampler2D gcolor;

uniform mat4 gbufferModelViewInverse;

uniform ivec2 eyeBrightnessSmooth;
uniform vec3 sunPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform int isEyeInWater;

varying vec2 texcoord;

vec3 view_coord_to_world_coord(vec3 view_coord) {
    vec3 world_coord = (gbufferModelViewInverse * vec4(view_coord, 1.0)).xyz;
    return world_coord;
}

vec3 jodieReinhardTonemap(vec3 c){
    // From: https://www.shadertoy.com/view/tdSXzD
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    vec3 tc = c / (c + 1.0);
    return mix(c / (l + 1.0), tc, tc);
}

/* DRAWBUFFERS: 0 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;

    vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
    float sunmoon_light_mix = smoothstep(-0.05, 0.05, sun_dir.y);
    float sky_brightness = SKY_ILLUMINATION_INTENSITY * mix(MOON_INTENSITY, 1, sunmoon_light_mix);

    /* EXPOSURE ADJUST */
#if AUTO_EXPOSURE_ENABLE
    float eye_brightness = (isEyeInWater == 1 ? 1 : eyeBrightnessSmooth.y / 240.0);
    eye_brightness = sky_brightness * eye_brightness * eye_brightness;
    color *= clamp(5 / eye_brightness, 0.25, 10);
#endif

    color *= pow(EXPOSURE, GAMMA) * vec3(TONE_R, TONE_G, TONE_B);

#if TONEMAP_ENABLE
    /* TONEMAP */
    color = jodieReinhardTonemap(color);
#endif
    
    /* GAMMA */
    color = pow(color, vec3(1 / GAMMA));
    
    gl_FragData[0] = vec4(color, 1.0);
}