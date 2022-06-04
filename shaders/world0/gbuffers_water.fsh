#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define ILLUMINATION_EPSILON 0.5
#define ILLUMINATION_MODE 0     // [0 1]
#define BLOCK_ILLUMINATION_COLOR_TEMPERATURE 4400   // [1000 1100 1200 1300 1400 1500 1600 1700 1800 1900 2000 2100 2200 2300 2400 2500 2600 2700 2800 2900 3000 3100 3200 3300 3400 3500 3600 3700 3800 3900 4000 4100 4200 4300 4400 4500 4600 4700 4800 4900 5000 5100 5200 5300 5400 5500 5600 5700 5800 5900 6000 6100 6200 6300 6400 6500 6600 6700 6800 6900 7000 7100 7200 7300 7400 7500 7600 7700 7800 7900 8000 8100 8200 8300 8400 8500 8600 8700 8800 8900 9000 9100 9200 9300 9400 9500 9600 9700 9800 9900 10000]

#define MOON_INTENSITY 2e-5

#define BLOCK_ILLUMINATION_INTENSITY 3.0   //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#define BLOCK_ILLUMINATION_PHYSICAL_CLOSEST 0.5    //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SKY_ILLUMINATION_INTENSITY 20.0  //[5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]
#define BASE_ILLUMINATION_INTENSITY 0.01  //[0.0 1e-7 2e-7 5e-7 1e-6 2e-6 5e-6 1e-4 2e-4 5e-4 1e-4 2e-4 5e-4 0.001 0.002 0.005 0.01 0.02 0.05 0.1]

#define LUT_WIDTH 512
#define LUT_HEIGHT 512

uniform sampler2D texture;
uniform sampler2D colortex15;

uniform float viewWidth;
uniform float viewHeight;
uniform vec3 sunPosition;

uniform mat4 gbufferModelViewInverse;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;
varying float block_id;

vec3 view_coord_to_world_coord(vec3 view_coord) {
    vec3 world_coord = (gbufferModelViewInverse * vec4(view_coord, 1.0)).xyz;
    return world_coord;
}

vec3 LUT_color_temperature(float temp) {
    return texture2D(colortex15, vec2((0.5 + (temp - 1000) / 9000 * 90) / LUT_WIDTH, 0.5 / LUT_HEIGHT)).rgb;
}

vec3 LUT_sun_color(vec3 sunDir) {
	float sunCosZenithAngle = sunDir.y;
    vec2 uv = vec2((0.5 + 255 * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0)) / LUT_WIDTH,
                   3.5 / LUT_HEIGHT);
    return texture2D(colortex15, uv).rgb;
}

vec3 LUT_sky_light() {
    vec2 uv = vec2(32.5 / LUT_WIDTH,
                   98.5 / LUT_HEIGHT);
    return texture2D(colortex15, uv).rgb;
}

/* DRAWBUFFERS:13457 */
void main() {
    vec4 blockColor = vec4(0.0);
    if (block_id < 1.5) {
        // texture
        blockColor = texture2D(texture, texcoord.st);
        blockColor.rgb *= color;

        /* INVERSE GAMMA */
        blockColor.rgb = pow(blockColor.rgb, vec3(GAMMA));

        // ILLUMINATION
        vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
        vec3 sun_light = LUT_sun_color(sun_dir);
        vec3 moon_light = vec3(MOON_INTENSITY);
        float sunmoon_light_mix = smoothstep(0.0, 0.05, sun_dir.y);
        vec3 sunmoon_light = SKY_ILLUMINATION_INTENSITY * mix(moon_light, sun_light, sunmoon_light_mix);
        vec3 sky_light = SKY_ILLUMINATION_INTENSITY * LUT_sky_light();

        vec3 block_illumination_color = LUT_color_temperature(BLOCK_ILLUMINATION_COLOR_TEMPERATURE);
        float block_light_g = lightMapCoord.s * 1.066667 - 0.03333333;
        float sky_light_g = lightMapCoord.t * 1.066667 - 0.03333333;

        #if ILLUMINATION_MODE
            vec3 block_light = BLOCK_ILLUMINATION_INTENSITY * block_light_g * block_illumination_color;
        #else
            float block_light_dist = 13 - clamp(15 * block_light_g - 1, 0, 13);
            block_light_dist = (1 - ILLUMINATION_EPSILON) * block_light_dist + ILLUMINATION_EPSILON * block_light_dist / (13 - block_light_dist) + BLOCK_ILLUMINATION_PHYSICAL_CLOSEST;
            vec3 block_light = BLOCK_ILLUMINATION_INTENSITY * BLOCK_ILLUMINATION_PHYSICAL_CLOSEST * BLOCK_ILLUMINATION_PHYSICAL_CLOSEST / (block_light_dist * block_light_dist) * block_illumination_color;
        #endif
        blockColor.rgb *= block_light + sky_light * sky_light_g * sky_light_g + BASE_ILLUMINATION_INTENSITY;
    }


    vec3 data = vec3(gl_FragCoord.z, lightMapCoord.s * 1.066667 - 0.03333333, lightMapCoord.t * 1.066667 - 0.03333333);

    gl_FragData[1] = blockColor;
    gl_FragData[2] = vec4(normal, block_id > 1.5 ? 1.0 : 0.0);
    gl_FragData[3] = vec4(normal, block_id < 1.5 ? 1.0 : 0.0);
    gl_FragData[0] = vec4(data, block_id > 1.5 ? 1.0 : 0.0);
    gl_FragData[4] = vec4(data, block_id < 1.5 ? 1.0 : 0.0);
}