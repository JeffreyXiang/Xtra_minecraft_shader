#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SKY_ILLUMINATION_INTENSITY 3.0  //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D depthtex0;

uniform vec3 fogColor;
uniform float sunAngle;

varying vec2 texcoord;

/* DRAWBUFFERS: 0 */
void main() {
    /* FOG */
    vec3 color = texture2D(gcolor, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).x;
    float dist = texture2D(gdepth, texcoord).x;

    float sun_angle = sunAngle < 0.5 ? 0.5 - 2 * abs(sunAngle - 0.25) : 0;
    float sun_moon_mix = smoothstep(0, 0.02, sun_angle);
    float sky_brightness = SKY_ILLUMINATION_INTENSITY * mix(0.005, 1, sun_moon_mix);
    vec3 fog_color = pow(fogColor, vec3(GAMMA));
    fog_color *= clamp(sky_brightness / 1.2, 1, 100);
    if (depth < 1)
        color = mix(color, fog_color, clamp(pow(dist, 4), 0, 1));
    gl_FragData[0] = vec4(color, 1.0);
}