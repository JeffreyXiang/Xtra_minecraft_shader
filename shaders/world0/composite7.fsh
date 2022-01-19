#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SKY_ILLUMINATION_INTENSITY 3.0  //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]

uniform sampler2D gcolor;
uniform sampler2D composite;

uniform ivec2 eyeBrightnessSmooth;
uniform float sunAngle;

varying vec2 texcoord;

/* DRAWBUFFERS: 0 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;
    vec3 bloom = texture2D(composite, texcoord).rgb;

    /* EXPOSURE ADJUST */
    float sun_angle = sunAngle < 0.5 ? 0.5 - 2 * abs(sunAngle - 0.25) : 0;
    float sun_moon_mix = smoothstep(0, 0.02, sun_angle);
    float sky_brightness = SKY_ILLUMINATION_INTENSITY * mix(0.005, 1, sun_moon_mix);
    float eye_brightness = sky_brightness * (eyeBrightnessSmooth.y) / 240.0;
    color *= clamp(1.2 / eye_brightness, 0, 1);

    /* GAMMA */
    color = pow(color, vec3(1 / GAMMA));

    /* BLOOM */
    color += bloom;
    
    gl_FragData[0] = vec4(color, 1.0);
}