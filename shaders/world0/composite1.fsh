#version 120

#define PI 3.1415926535898
#define PHI 0.6180339887498949

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define TAA_ENABLE 1 // [0 1]

const int shadowMapResolution = 4096;   //[1024 2048 4096]

#define SHADOW_INTENSITY 0.95    // [0.5 0.6 0.7 0.75 0.8 0.85 0.9 0.925 0.95 0.975 1.0]
#define SHADOW_AA_ENABLE 1 //[0 1]
#define SHADOW_AA_SAMPLE 64 //[4 8 16 32 64 128 256]
#define SHADOW_FISHEY_LENS_INTENSITY 0.85
#define SHADOW_EPSILON (5e2 / shadowMapResolution * (SHADOW_AA_ENABLE == 1 ? 2 : 1))
#define SHADOW_EPSILON2 (2e-1 / shadowMapResolution * (SHADOW_AA_ENABLE == 1 ? 2 : 1))

#define ILLUMINATION_EPSILON 0.5
#define ILLUMINATION_MODE 0     // [0 1]
#define BLOCK_ILLUMINATION_COLOR_TEMPERATURE 4400   // [1000 1100 1200 1300 1400 1500 1600 1700 1800 1900 2000 2100 2200 2300 2400 2500 2600 2700 2800 2900 3000 3100 3200 3300 3400 3500 3600 3700 3800 3900 4000 4100 4200 4300 4400 4500 4600 4700 4800 4900 5000 5100 5200 5300 5400 5500 5600 5700 5800 5900 6000 6100 6200 6300 6400 6500 6600 6700 6800 6900 7000 7100 7200 7300 7400 7500 7600 7700 7800 7900 8000 8100 8200 8300 8400 8500 8600 8700 8800 8900 9000 9100 9200 9300 9400 9500 9600 9700 9800 9900 10000]

#define MOON_INTENSITY 2e-5

#define BLOCK_ILLUMINATION_INTENSITY 3.0   //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#define BLOCK_ILLUMINATION_PHYSICAL_CLOSEST 0.5    //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SKY_ILLUMINATION_INTENSITY 20.0  //[5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]
#define BASE_ILLUMINATION_INTENSITY 0.01  //[0.0 1e-7 2e-7 5e-7 1e-6 2e-6 5e-6 1e-4 2e-4 5e-4 1e-4 2e-4 5e-4 0.001 0.002 0.005 0.01 0.02 0.05 0.1]

#define FOG_AIR_DECAY 0.001     //[0.0 0.0001 0.0002 0.0005 0.001 0.002 0.005 0.01 0.02 0.05]
#define FOG_THICKNESS 256
#define FOG_WATER_DECAY 0.1     //[0.01 0.02 0.05 0.1 0.2 0.5 1.0]

#define LUT_WIDTH 512
#define LUT_HEIGHT 512

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D colortex15;
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;

uniform float far;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform int isEyeInWater;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

const float Halton2[] = float[](1./2, 1./4, 3./4, 1./8, 5./8, 3./8, 7./8, 1./16);
const float Halton3[] = float[](1./3, 2./3, 1./9, 4./9, 7./9, 2./9, 5./9, 8./9);

varying vec2 texcoord;

vec2 shadowmap_offset(vec2 ori) {
    return vec2(ori.x / shadowMapResolution, ori.y / shadowMapResolution);
}

vec2 shadowmap_nearest(vec2 texcoord) {
    return vec2((floor(texcoord.s * shadowMapResolution) + 0.5) / shadowMapResolution, (floor(texcoord.t * shadowMapResolution) + 0.5) / shadowMapResolution);
}

vec2 fish_len_distortion(vec2 ndc_coord_xy) {
    float dist = length(ndc_coord_xy);
    float distort = (1.0 - SHADOW_FISHEY_LENS_INTENSITY) + dist * SHADOW_FISHEY_LENS_INTENSITY;
    return ndc_coord_xy.xy / distort;
}

float fish_len_distortion_grad(float dist) {
    float distort = (1.0 - SHADOW_FISHEY_LENS_INTENSITY) + dist * SHADOW_FISHEY_LENS_INTENSITY;
    return (1.0 - SHADOW_FISHEY_LENS_INTENSITY) / (distort * distort);
}

vec3 screen_coord_to_view_coord(vec3 screen_coord) {
    vec4 ndc_coord = vec4(screen_coord * 2 - 1, 1);
    vec4 clip_coord = gbufferProjectionInverse * ndc_coord;
    vec3 view_coord = clip_coord.xyz / clip_coord.w;
    return view_coord;
}

vec3 view_coord_to_world_coord(vec3 view_coord) {
    vec3 world_coord = (gbufferModelViewInverse * vec4(view_coord, 1.0)).xyz;
    return world_coord;
}

vec3 world_coord_to_shadow_coord(vec3 world_coord) {
    vec4 shadow_view_coord = shadowModelView * vec4(world_coord, 1);
    vec4 shadow_clip_coord = shadowProjection * shadow_view_coord;
    vec4 shadow_ndc_coord = vec4(shadow_clip_coord.xyz / shadow_clip_coord.w, 1.0);
    vec3 shadow_screen_coord = shadow_ndc_coord.xyz * 0.5 + 0.5;
    return shadow_screen_coord;
}

float fog(float dist, float decay) {
    dist = dist < 0 ? 0 : dist;
    dist = dist * decay / 16 + 1;
    dist = dist * dist;
    dist = dist * dist;
    dist = dist * dist;
    dist = dist * dist;
    return 1 / dist;
}

vec2 Fibonacci_disk_sample(int n, int total) {
    float theta = 2 * PI * fract(PHI * n);
    float r = sqrt(float(n) / total);
    return vec2(r * cos(theta), r * sin(theta));
}

int is_shadow_border(vec2 shadow_texcoord, float shadow_depth) {
    // shadow_texcoord = shadowmap_nearest(shadow_texcoord);
    float shadow_00 = shadow2D(shadowtex1, vec3(shadow_texcoord + shadowmap_offset(vec2(-2, -2)), shadow_depth)).z;
    float shadow_01 = shadow2D(shadowtex1, vec3(shadow_texcoord + shadowmap_offset(vec2(-2,  2)), shadow_depth)).z;
    float shadow_10 = shadow2D(shadowtex1, vec3(shadow_texcoord + shadowmap_offset(vec2( 2, -2)), shadow_depth)).z;
    float shadow_11 = shadow2D(shadowtex1, vec3(shadow_texcoord + shadowmap_offset(vec2( 2,  2)), shadow_depth)).z;
    float min_ = min(min(shadow_00, shadow_01), min(shadow_10, shadow_11));
    float max_ = max(max(shadow_00, shadow_01), max(shadow_10, shadow_11));
    if (min_ < 1 && max_ > 0) return 1;
    shadow_00 = shadow2D(shadowtex1, vec3(shadow_texcoord + shadowmap_offset(vec2(-1, -1)), shadow_depth)).z;
    shadow_01 = shadow2D(shadowtex1, vec3(shadow_texcoord + shadowmap_offset(vec2(-1,  1)), shadow_depth)).z;
    shadow_10 = shadow2D(shadowtex1, vec3(shadow_texcoord + shadowmap_offset(vec2( 1, -1)), shadow_depth)).z;
    shadow_11 = shadow2D(shadowtex1, vec3(shadow_texcoord + shadowmap_offset(vec2( 1,  1)), shadow_depth)).z;
    min_ = min(min(shadow_00, shadow_01), min(shadow_10, shadow_11));
    max_ = max(max(shadow_00, shadow_01), max(shadow_10, shadow_11));
    return (min_ < 1 && max_ > 0) ? 1 : 0;
}

vec3 LUT_color_temperature(float temp) {
    return texture2D(colortex15, vec2((0.5 + (temp - 1000) / 9000 * 90) / LUT_WIDTH, 0.5 / LUT_HEIGHT)).rgb;
}

vec3 LUT_water_absorption(float decay) {
    return texture2D(colortex15, vec2((0.5 + (1 - decay) * 255) / LUT_WIDTH, 1.5 / LUT_HEIGHT)).rgb;
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

/* RENDERTARGETS: 0 */
void main() {
    vec4 normal_data_s = texture2D(gnormal, texcoord);
    vec3 normal_s = normal_data_s.rgb;
    float block_id_s = normal_data_s.a;
    vec3 color_s = texture2D(gcolor, texcoord).rgb;
    if (block_id_s > 0.5) {
        vec3 depth_data = texture2D(gdepth, texcoord).xyz;
        float depth_s = depth_data.x;
        float depth_w = depth_data.y;
        float depth_g = depth_data.z;
        vec2 lum_data = texture2D(gaux3, texcoord).xy;
        float block_light_s = lum_data.x;
        float sky_light_s = lum_data.y;
        float dist_w = texture2D(gaux4, texcoord).y;

        vec3 block_illumination_color = LUT_color_temperature(BLOCK_ILLUMINATION_COLOR_TEMPERATURE);

        /* SHADOW */
        vec3 screen_coord = vec3(texcoord, depth_s);
        #if TAA_ENABLE
            int idx = int(mod(frameCounter, 8));
            screen_coord.st -= vec2((Halton2[idx] - 0.5) / viewWidth, (Halton3[idx] - 0.5) / viewHeight);
        #endif
        vec3 view_coord = screen_coord_to_view_coord(screen_coord);
        vec3 light_direction = normalize(10 * shadowLightPosition - view_coord);
        float shadow_sin_ = dot(light_direction, normal_s);
        float shadow_cos_ = sqrt(1 - shadow_sin_ * shadow_sin_);
        float shadow_cot_ = shadow_cos_ / shadow_sin_;
        vec3 world_coord = view_coord_to_world_coord(view_coord);
        vec3 shadow_coord = world_coord_to_shadow_coord(world_coord);
        float shadow_dist = length(shadow_coord.xy * 2 - 1);
        float water_current_depth = shadow_coord.z;
        float shadow_depth = abs(dot(view_coord, light_direction) * dot(normal_s, light_direction));
        float k = SHADOW_EPSILON / fish_len_distortion_grad(shadow_dist);
        view_coord += k * mix(shadow_cos_ * normal_s, shadow_cot_ * light_direction, clamp(0.05 / (k * shadow_cot_), 0, 1));
        k = SHADOW_EPSILON2 * shadow_depth * shadow_depth;
        view_coord += k * light_direction;
        world_coord = view_coord_to_world_coord(view_coord);
        shadow_coord = world_coord_to_shadow_coord(world_coord);
        float shadow_dist_weight = 1 - smoothstep(0.75, 0.95, shadow_dist);
        float current_depth = shadow_coord.z;
        vec2 shadow_texcoord = fish_len_distortion(shadow_coord.xy * 2 - 1) * 0.5 + 0.5;
        float in_shadow = 1 - shadow2D(shadowtex1, vec3(shadow_texcoord, current_depth)).z;
        #if SHADOW_AA_ENABLE
        if (is_shadow_border(shadow_texcoord, current_depth) == 1) {
            in_shadow = 0;
            for (int i = 0; i < SHADOW_AA_SAMPLE; i++) {
                in_shadow += 1 - shadow2D(shadowtex1, vec3(
                    shadow_texcoord + 2 * shadowmap_offset(Fibonacci_disk_sample(i, SHADOW_AA_SAMPLE)),
                    current_depth
                )).z;
            }
            in_shadow /= SHADOW_AA_SAMPLE;
        }
        #endif
        in_shadow *= shadow_dist_weight;
        in_shadow = shadow_sin_ < 0 ? 1 : in_shadow;
        float sun_light_shadow = smoothstep(0.0, 0.05, shadow_sin_);
        sun_light_shadow *= 1 - in_shadow;
        sun_light_shadow = 1 - sun_light_shadow;

        /* ILLUMINATION */
        vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
        vec3 sun_light = LUT_sun_color(sun_dir);
        vec3 moon_light = vec3(MOON_INTENSITY);
        float sunmoon_light_mix = smoothstep(0.0, 0.05, sun_dir.y);
        vec3 sunmoon_light = SKY_ILLUMINATION_INTENSITY * mix(moon_light, sun_light, sunmoon_light_mix);
        vec3 sky_light = SKY_ILLUMINATION_INTENSITY * LUT_sky_light() + (1 - SHADOW_INTENSITY) * sunmoon_light;
        sunmoon_light *= SHADOW_INTENSITY;
        if (isEyeInWater == 0 && depth_w < 1.5 || isEyeInWater == 1 && (depth_w > 1.5 || depth_g < depth_w)) {
            float shadow_water_dist = -((water_current_depth - texture2D(shadowtex0, shadow_texcoord).x) * 2 - 1 - shadowProjection[3][2]) / shadowProjection[2][2];
            shadow_water_dist = shadow_water_dist < 0 ? 0 : shadow_water_dist;
            float k = fog((1 - sky_light_s) * 15, FOG_WATER_DECAY);
            sky_light *= k * LUT_water_absorption(k);
            k = fog(shadow_water_dist, FOG_WATER_DECAY);
            sunmoon_light *= k * LUT_water_absorption(k);
        } 

        #if ILLUMINATION_MODE
            vec3 block_light = BLOCK_ILLUMINATION_INTENSITY * block_light_s * block_illumination_color;
        #else
            float block_light_dist = block_id_s > 1.5 ? 0 : 13 - clamp(15 * block_light_s - 1, 0, 13);
            block_light_dist = (1 - ILLUMINATION_EPSILON) * block_light_dist + ILLUMINATION_EPSILON * block_light_dist / (13 - block_light_dist) + BLOCK_ILLUMINATION_PHYSICAL_CLOSEST;
            vec3 block_light = BLOCK_ILLUMINATION_INTENSITY * BLOCK_ILLUMINATION_PHYSICAL_CLOSEST * BLOCK_ILLUMINATION_PHYSICAL_CLOSEST / (block_light_dist * block_light_dist) * block_illumination_color;
        #endif

        k = fog(FOG_THICKNESS, FOG_AIR_DECAY);
        sky_light *= (in_shadow > 0.5 ? sky_light_s * sky_light_s : 1) * k;
        sunmoon_light *= (1 - sun_light_shadow) * k;
        color_s *= block_light + sky_light + sunmoon_light + BASE_ILLUMINATION_INTENSITY;
    }
    
    gl_FragData[0] = vec4(color_s, 1.0);
}