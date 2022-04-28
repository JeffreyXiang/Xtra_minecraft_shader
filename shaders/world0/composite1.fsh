#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

const int shadowMapResolution = 4096;   //[1024 2048 4096]

#define SHADOW_EPSILON (5e2 / shadowMapResolution)
#define SHADOW_INTENSITY 0.95    // [0.5 0.6 0.7 0.75 0.8 0.85 0.9 0.925 0.95 0.975 1.0]
#define SHADOW_FISHEY_LENS_INTENSITY 0.85

#define ILLUMINATION_EPSILON 0.5
#define ILLUMINATION_MODE 0     // [0 1]
#define BLOCK_ILLUMINATION_COLOR_TEMPERATURE 4400   // [1000 1100 1200 1300 1400 1500 1600 1700 1800 1900 2000 2100 2200 2300 2400 2500 2600 2700 2800 2900 3000 3100 3200 3300 3400 3500 3600 3700 3800 3900 4000 4100 4200 4300 4400 4500 4600 4700 4800 4900 5000 5100 5200 5300 5400 5500 5600 5700 5800 5900 6000 6100 6200 6300 6400 6500 6600 6700 6800 6900 7000 7100 7200 7300 7400 7500 7600 7700 7800 7900 8000 8100 8200 8300 8400 8500 8600 8700 8800 8900 9000 9100 9200 9300 9400 9500 9600 9700 9800 9900 10000]

#define MOON_INTENSITY 2.533e-6
#define SUN_SRAD 2.101e1

#define BLOCK_ILLUMINATION_INTENSITY 3.0   //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#define BLOCK_ILLUMINATION_PHYSICAL_CLOSEST 0.5    //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SKY_ILLUMINATION_INTENSITY 20.0  //[5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]
#define BASE_ILLUMINATION_INTENSITY 0.01  //[0.001 0.002 0.005 0.01 0.02 0.05 0.1]

#define FOG_AIR_DECAY 0.001     //[0.0001 0.0002 0.0005 0.001 0.002 0.005 0.01 0.02 0.05]
#define FOG_THICKNESS 256
#define FOG_WATER_DECAY 0.1     //[0.01 0.02 0.05 0.1 0.2 0.5 1.0]

#define ATMOSPHERE_SAMPLES 32

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
uniform float sunAngle;
uniform int isEyeInWater;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

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
    vec4 clid_coord = gbufferProjectionInverse * ndc_coord;
    vec3 view_coord = clid_coord.xyz / clid_coord.w;
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

vec3 LUT_color_temperature(float temp) {
    return texture2D(colortex15, vec2((0.5 + (temp - 1000) / 9000 * 90) / viewWidth, 0.5 / viewHeight)).rgb;
}

vec3 LUT_water_absorption(float decay) {
    return texture2D(colortex15, vec2((0.5 + (1 - decay) * 255) / viewWidth, 1.5 / viewHeight)).rgb;
}

vec3 LUT_sun_color(vec3 sunDir) {
	float sunCosZenithAngle = sunDir.y;
    vec2 uv = vec2((0.5 + 255 * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0)) / viewWidth,
                   3.5 / viewHeight);
    return texture2D(colortex15, uv).rgb;
}

// Atmosphere Parameters

const float groundRadiusMM = 6.360;
const float atmosphereRadiusMM = 6.460;

const vec3 rayleighScatteringBase = vec3(5.802, 13.558, 33.1);
const float rayleighAbsorptionBase = 0.0;

const float mieScatteringBase = 3.996;
const float mieAbsorptionBase = 4.4;

const vec3 ozoneAbsorptionBase = vec3(0.650, 1.881, .085);

const vec3 viewPos = vec3(0.0, groundRadiusMM + 0.0001, 0.0);

vec3 LUT_atmosphere_transmittance(vec3 pos, vec3 sunDir) {
    float height = length(pos);
    vec3 up = pos / height;
	float sunCosZenithAngle = dot(sunDir, up);
    vec2 uv = vec2((0.5 + 255 * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0)) / viewWidth,
                   (3.5 + 63 * clamp((height - groundRadiusMM) / (atmosphereRadiusMM - groundRadiusMM), 0, 1)) / viewHeight);
    return texture2D(colortex15, uv).rgb;
}

vec3 LUT_atmosphere_multiple_scattering(vec3 pos, vec3 sunDir) {
    float height = length(pos);
    vec3 up = pos / height;
	float sunCosZenithAngle = dot(sunDir, up);
    vec2 uv = vec2((0.5 + 31 * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0)) / viewWidth,
                   (67.5 + 31 * clamp((height - groundRadiusMM) / (atmosphereRadiusMM - groundRadiusMM), 0, 1)) / viewHeight);
    return texture2D(colortex15, uv).rgb;
}

float getMiePhase(float cosTheta) {
    const float g = 0.8;
    const float scale = 3.0 / (8.0 * PI);
    
    float num = (1.0 - g * g) * (1.0 + cosTheta * cosTheta);
    float denom = (2.0 + g * g)*pow((1.0 + g * g - 2.0 * g * cosTheta), 1.5);
    
    return scale * num / denom;
}

float getRayleighPhase(float cosTheta) {
    const float k = 3.0 / (16.0 * PI);
    return k * (1.0 + cosTheta * cosTheta);
}

float rayIntersectSphere(vec3 ro, vec3 rd, float rad) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - rad*rad;
    if (c > 0.0f && b > 0.0) return -1.0;
    float discr = b*b - c;
    if (discr < 0.0) return -1.0;
    // Special case: inside sphere, use far discriminant
    if (discr > b*b) return (-b + sqrt(discr));
    return -b - sqrt(discr);
}

void getScatteringValues(vec3 pos, 
                         out vec3 rayleighScattering, 
                         out float mieScattering,
                         out vec3 extinction) {
    float altitudeKM = (length(pos)-groundRadiusMM)*1000.0;
    // Note: Paper gets these switched up.
    float rayleighDensity = min(exp(-altitudeKM/8.0), 10);
    float mieDensity = min(exp(-altitudeKM/1.2), 10);
    
    rayleighScattering = rayleighScatteringBase*rayleighDensity;
    float rayleighAbsorption = rayleighAbsorptionBase*rayleighDensity;
    
    mieScattering = mieScatteringBase*mieDensity;
    float mieAbsorption = mieAbsorptionBase*mieDensity;
    
    vec3 ozoneAbsorption = ozoneAbsorptionBase*max(0.0, 1.0 - abs(altitudeKM-25.0)/15.0);
    
    extinction = rayleighScattering + rayleighAbsorption + mieScattering + mieAbsorption + ozoneAbsorption;
}

vec3 raymarchScattering(vec3 pos, 
                        vec3 rayDir, 
                        vec3 sunDir,
                        float tMax,
                        int numSteps) {
    float cosTheta = dot(rayDir, sunDir);
    
	float miePhaseValue = getMiePhase(cosTheta);
	float rayleighPhaseValue = getRayleighPhase(-cosTheta);
    
    vec3 lum = vec3(0.0);
    vec3 transmittance = vec3(1.0);
    float t = 0.0;
    for (int i = 0; i < numSteps; i++) {
        float newT = ((i + 0.3)/numSteps)*tMax;
        float dt = newT - t;
        t = newT;
        
        vec3 newPos = pos + t*rayDir;
        
        vec3 rayleighScattering, extinction;
        float mieScattering;
        getScatteringValues(newPos, rayleighScattering, mieScattering, extinction);
        
        vec3 sampleTransmittance = exp(-dt*extinction);

        vec3 sunTransmittance = LUT_atmosphere_transmittance(newPos, sunDir);
        vec3 psiMS = LUT_atmosphere_multiple_scattering(newPos, sunDir);
        
        vec3 rayleighInScattering = rayleighScattering*(rayleighPhaseValue*sunTransmittance + psiMS);
        vec3 mieInScattering = mieScattering*(miePhaseValue*sunTransmittance + psiMS);
        vec3 inScattering = (rayleighInScattering + mieInScattering);

        // Integrated scattering within path segment.
        vec3 scatteringIntegral = (inScattering - inScattering * sampleTransmittance) / extinction;

        lum += scatteringIntegral*transmittance;
        
        transmittance *= sampleTransmittance;
    }
    return lum;
}

/* RENDERTARGETS: 0,15 */
void main() {
    vec4 normal_data_s = texture2D(gnormal, texcoord);
    vec3 normal_s = normal_data_s.rgb;
    float block_id_s = normal_data_s.a;
    vec3 color_s;
    if (block_id_s > 0.5) {
        color_s = texture2D(gcolor, texcoord).rgb;
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
        vec3 view_coord = screen_coord_to_view_coord(screen_coord);
        vec3 light_direction = normalize(10 * shadowLightPosition - view_coord);
        float shadow_dist = length(view_coord - dot(view_coord, light_direction) * light_direction) / 160;
        float shadow_sin_ = dot(light_direction, normal_s);
        float shadow_cos_ = sqrt(1 - shadow_sin_ * shadow_sin_);
        float shadow_cot_ = shadow_cos_ / shadow_sin_;
        float k = SHADOW_EPSILON / fish_len_distortion_grad(shadow_dist);
        view_coord += k * mix(shadow_cos_ * normal_s, shadow_cot_ * light_direction, clamp(0.05 / (k * shadow_cot_), 0, 1));
        vec3 world_coord = view_coord_to_world_coord(view_coord);
        vec3 shadow_coord = world_coord_to_shadow_coord(world_coord);
        // float shadow_dist_weight = 1 - smoothstep(0.75, 0.9, shadow_dist / far);
        float current_depth = shadow_coord.z;
        vec2 shadow_texcoord = fish_len_distortion(shadow_coord.xy * 2 - 1) * 0.5 + 0.5;
        float sun_light_shadow = smoothstep(0.0, 0.05, shadow_sin_);
        float in_shadow = shadow_sin_ < 0 ? 1 : 1 - shadow2D(shadowtex1, vec3(shadow_texcoord, current_depth)).z;
        sun_light_shadow *= 1 - in_shadow;
        sun_light_shadow = 1 - sun_light_shadow;
        // sun_light_shadow *= shadow_dist_weight;

        /* ILLUMINATION */
        float sun_angle = sunAngle < 0.25 ? 0.25 - sunAngle : sunAngle < 0.75 ? sunAngle - 0.25 : 1.25 - sunAngle;
        sun_angle = 1 - 4 * sun_angle;
        vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
        vec3 sun_light = LUT_sun_color(sun_dir);
        vec3 moon_light = vec3(MOON_INTENSITY);
        float sky_light_mix = smoothstep(-0.05, 0.05, sun_angle);
        vec3 sky_light = SKY_ILLUMINATION_INTENSITY * mix(moon_light, sun_light, sky_light_mix);
        float sky_brightness = SKY_ILLUMINATION_INTENSITY * mix(MOON_INTENSITY, 1, sky_light_mix);
        float sunmoon_light_mix = smoothstep(-0.05, 0.05, sun_angle);
        vec3 sunmoon_light = SKY_ILLUMINATION_INTENSITY * mix(moon_light, sun_light, sunmoon_light_mix);
        vec3 sunmoon_lum = sunmoon_light;
        if (isEyeInWater == 0 && depth_w < 1.5 || isEyeInWater == 1 && (depth_w > 1.5 || depth_g < depth_w)) {
            float shadow_water_dist = -((current_depth - texture2D(shadowtex0, shadow_texcoord).x) * 2 - 1 - shadowProjection[3][2]) / shadowProjection[2][2];
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
        sky_light *= (in_shadow > 0.5 ? sky_light_s * sky_light_s : 1) * (1 - SHADOW_INTENSITY * k);
        sunmoon_light *= (1 - sun_light_shadow) * SHADOW_INTENSITY * k;
        color_s *= block_light + sky_light + sunmoon_light + BASE_ILLUMINATION_INTENSITY;
    }
    
    gl_FragData[0] = vec4(color_s, 1.0);

    /* LUT SKY */
    vec4 LUT_data = texture2D(colortex15, texcoord);
    vec2 LUT_texcoord = vec2(texcoord.x / 256 * viewWidth, texcoord.y / 256 * viewHeight);
    LUT_texcoord.y = (LUT_texcoord.y * 256 - 99) / 128;

    if (LUT_texcoord.x > 0 && LUT_texcoord.x < 1 && LUT_texcoord.y > 0 && LUT_texcoord.y < 1) {
        float u = (LUT_texcoord.x * 256 - 0.5) / 255;
        float v = (LUT_texcoord.y * 128 - 0.5) / 127;
        
        float azimuthAngle = (u - 0.5) * 2.0 * PI;
        float adjV;
        if (v < 0.5) {
            float coord = 1.0 - 2.0*v;
            adjV = -coord*coord;
        } else {
            float coord = v*2.0 - 1.0;
            adjV = coord*coord;
        }
        
        float height = length(viewPos);
        vec3 up = viewPos / height;
        float horizonAngle = acos(sqrt(height * height - groundRadiusMM * groundRadiusMM) / height) - 0.5 * PI;
        float altitudeAngle = adjV*0.5*PI - horizonAngle;
        
        float cosAltitude = cos(altitudeAngle);
        vec3 rayDir = vec3(cosAltitude*sin(azimuthAngle), sin(altitudeAngle), -cosAltitude*cos(azimuthAngle));
        
        vec3 sunDir = normalize(view_coord_to_world_coord(sunPosition));
        
        float atmoDist = rayIntersectSphere(viewPos, rayDir, atmosphereRadiusMM);
        float groundDist = rayIntersectSphere(viewPos, rayDir, groundRadiusMM);
        float tMax = (groundDist < 0.0) ? atmoDist : min(groundDist+1, atmoDist);
        vec3 lum = raymarchScattering(viewPos, rayDir, sunDir, tMax, ATMOSPHERE_SAMPLES);
        LUT_data = vec4(lum, 1.0);
    }
    
    gl_FragData[1] = LUT_data;
}