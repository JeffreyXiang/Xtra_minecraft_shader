#version 120

#define PI 3.1415926535898

#define MOON_INTENSITY 2e-5
#define SUN_SRAD 2e1
#define MOON_SRAD 5e1

#define SKY_ILLUMINATION_INTENSITY 20.0  //[5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]

#define ATMOSPHERE_SAMPLES 32

#define CLOUDS_ENABLE 1 // [0 1]
#define CLOUDS_RATIO 0.3 // [0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define CLOUDS_SAMPLES 128
#define CLOUDS_SCATTER_BASE 10000
#define CLOUDS_ABSORB_BASE 10000
#define CLOUDS_WIND vec2(0.26861928, 0.96324643)
#define CLOUDS_NV0 vec2(-0.0806,  0.1613)
#define CLOUDS_NV1 vec2(-0.0602, -0.1844)
#define CLOUDS_NV2 vec2( 0.1758,  0.1074)
#define CLOUDS_NV3 vec2(-0.0480, -0.0813)
#define CLOUDS_NV4 vec2( 0.2454,  0.2085)
#define CLOUDS_NV5 vec2( 0.0343, -0.3817)

#define LUT_WIDTH 512
#define LUT_HEIGHT 512

#if CLOUDS_ENABLE
uniform sampler2D noisetex;
uniform sampler3D colortex14;
#endif
uniform sampler2D colortex15;

uniform vec3 sunPosition;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

uniform mat4 gbufferModelViewInverse;

varying vec2 texcoord;

vec3 view_coord_to_world_coord(vec3 view_coord) {
    vec3 world_coord = (gbufferModelViewInverse * vec4(view_coord, 1.0)).xyz;
    return world_coord;
}

// Atmosphere Parameters

const float groundRadiusMM = 6.360;
const float atmosphereRadiusMM = 6.460;

const vec3 rayleighScatteringBase = vec3(5.802, 13.558, 33.1);
const float rayleighAbsorptionBase = 0.0;

const float mieScatteringBase = 3.996;
const float mieAbsorptionBase = 4.4;

const vec3 ozoneAbsorptionBase = vec3(0.650, 1.881, .085);

const vec3 viewPos = vec3(0.0, groundRadiusMM, 0.0);

vec3 LUT_atmosphere_transmittance(vec3 pos, vec3 sunDir) {
    float height = length(pos);
    vec3 up = pos / height;
	float sunCosZenithAngle = dot(sunDir, up);
    vec2 uv = vec2((0.5 + 255 * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0)) / LUT_WIDTH,
                   (3.5 + 63 * clamp((height - groundRadiusMM) / (atmosphereRadiusMM - groundRadiusMM), 0, 1)) / LUT_HEIGHT);
    return texture2D(colortex15, uv).rgb;
}

vec3 LUT_atmosphere_multiple_scattering(vec3 pos, vec3 sunDir) {
    float height = length(pos);
    vec3 up = pos / height;
	float sunCosZenithAngle = dot(sunDir, up);
    vec2 uv = vec2((0.5 + 31 * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0)) / LUT_WIDTH,
                   (67.5 + 31 * clamp((height - groundRadiusMM) / (atmosphereRadiusMM - groundRadiusMM), 0, 1)) / LUT_HEIGHT);
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

vec2 rayIntersectSphere(vec3 ro, vec3 rd, float rad) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - rad*rad;
    if (c > 0.0f && b > 0.0) return vec2(-1.0);
    float discr = b*b - c;
    if (discr < 0.0) return vec2(-1.0);
    discr = sqrt(discr);
    return vec2(-b - discr, -b + discr);
}

void getScatteringValues(
        vec3 pos, 
        out vec3 rayleighScattering, 
        out float mieScattering,
        out vec3 extinction
    ) {
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

void raymarchScattering(
        vec3 pos, 
        vec3 rayDir, 
        vec3 sunDir,
        float tMin,
        float tMax,
        int numSteps,
        out vec3 lum,
        out vec3 transmittance
    ) {
    float cosTheta = dot(rayDir, sunDir);
    
	float miePhaseValue = getMiePhase(cosTheta);
	float rayleighPhaseValue = getRayleighPhase(-cosTheta);
    
    lum = vec3(0.0);
    transmittance = vec3(1.0);
    float t = tMin;
    for (int i = 0; i < numSteps; i++) {
        float newT = tMin + ((i + 0.3)/numSteps)*(tMax - tMin);
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
}

#if CLOUDS_ENABLE
const float cloudBottomRadiusMM = 6.3605;
const float cloudHeightMM = 0.001;
const float cloudRenderMaxRadiusMM = 6.38;

float cloud_weight(float cloud_fract) {
    return smoothstep(0, 0.02, cloud_fract) * smoothstep(0.9, 0.98, 1 - cloud_fract);
}

float remap(float v, float ori_l, float ori_h, float new_l, float new_h) {
    return clamp((v - ori_l) / (ori_h - ori_l), 0, 1) * (new_h - new_l) + new_l;
}

void raymarchClouds(
        vec3 pos, 
        vec3 rayDir, 
        vec3 sunDir,
        float tMin,
        float tMax,
        int numSteps,
        out vec3 lum,
        out float transmittance
    ) {
    lum = vec3(0.0);
    transmittance = 1.0;
    float sunmoon_light_mix = smoothstep(0.0, 0.05, sunDir.y);
    float t = tMin;
    float divide = tMin + cloudHeightMM;
    float sqrt_divide;
    if (divide < tMax) {
        sqrt_divide = sqrt(tMin + cloudHeightMM);
        tMax = sqrt(tMax) * sqrt_divide;
    }
    for (int i = 0; i < numSteps; i++) {
        float newT = tMin + ((i + 0.3)/numSteps)*(tMax - tMin);
        if (newT > divide) {
            newT /= sqrt_divide;
            newT = newT * newT;
        }
        float dt = newT - t;
        t = newT;
        
        vec3 newPos = pos + t*rayDir;
        float cloud_fract = 0.1 * (length(newPos) - cloudBottomRadiusMM) / cloudHeightMM;

        float offset = (
            texture2D(noisetex, fract(newPos.xz / 7.4279 + frameTimeCounter * 5e-4 * CLOUDS_NV0)).r +
            texture2D(noisetex, fract(newPos.xz / 7.4279 + frameTimeCounter * 5e-4 * CLOUDS_NV1)).r +
            texture2D(noisetex, fract(newPos.xz / 7.4279 + frameTimeCounter * 5e-4 * CLOUDS_NV2)).g +
            texture2D(noisetex, fract(newPos.xz / 7.4279 + frameTimeCounter * 5e-4 * CLOUDS_NV3)).g +
            texture2D(noisetex, fract(newPos.xz / 7.4279 + frameTimeCounter * 5e-4 * CLOUDS_NV4)).b +
            texture2D(noisetex, fract(newPos.xz / 7.4279 + frameTimeCounter * 5e-4 * CLOUDS_NV5)).b - 3
            ) / 6;

        float density = cloud_weight(cloud_fract) * remap(
            texture3D(colortex14, vec3(
                newPos.xz / 0.0219721 + frameTimeCounter * CLOUDS_WIND * 2e-3,
                cloud_fract - frameTimeCounter * 5e-3 + offset)).r,
            1 - CLOUDS_RATIO, 1, 0, 1);
        float extinction = (CLOUDS_SCATTER_BASE + CLOUDS_ABSORB_BASE) * density;
        float scatterring = CLOUDS_SCATTER_BASE * density;
        float sampleTransmittance = exp(-dt*extinction);
        float k = density * 1;
        vec3 sunmoon_light = mix(vec3(MOON_INTENSITY), LUT_atmosphere_transmittance(newPos, sunDir), sunmoon_light_mix);
        vec3 scatteringIntegral = scatterring * (1 - sampleTransmittance) / (extinction + 1e-6)
            * exp(-k) * (1 - exp(-2 * k))
            * sunmoon_light;

        lum += scatteringIntegral*transmittance;
        transmittance *= sampleTransmittance;
    }
}
#endif

/* RENDERTARGETS: 15 */
void main() {
    vec3 view_pos = viewPos + vec3(0, cameraPosition.y * 1e-6, 0);
    vec4 LUT_data = texture2D(colortex15, texcoord);

    float height = length(view_pos);
    float horizonAngle = height > groundRadiusMM ? -asin(sqrt(height * height - groundRadiusMM * groundRadiusMM) / height) : 0;

    /* LUT SKY */
    vec2 LUT_texcoord = vec2((texcoord.x * LUT_WIDTH - 256) / 256 , (texcoord.y * LUT_HEIGHT) / 256);
    if (LUT_texcoord.x > 0 && LUT_texcoord.x < 1 && LUT_texcoord.y > 0 && LUT_texcoord.y < 1) {
        float u = (LUT_texcoord.x * 256 - 0.5) / 255;
        float v = (LUT_texcoord.y * 256 - 0.5) / 255;
        
        float azimuthAngle = (u - 0.5) * 2.0 * PI;
        
        float coord = 2 * v - 1;
        float altitudeAngle = coord*coord*(sign(coord)*0.5*PI-horizonAngle) + horizonAngle;
        
        float cosAltitude = cos(altitudeAngle);
        vec3 rayDir = vec3(cosAltitude*sin(azimuthAngle), sin(altitudeAngle), -cosAltitude*cos(azimuthAngle));
        
        vec3 sunDir = normalize(view_coord_to_world_coord(sunPosition));
        
        float tMin, tMax;
        vec3 lum=vec3(0.0), transmittance=vec3(1.0);
        vec2 atmoDist = rayIntersectSphere(view_pos, rayDir, atmosphereRadiusMM);
        vec2 groundDist = rayIntersectSphere(view_pos, rayDir, groundRadiusMM);
        if (atmoDist.y > 0) {
            if (height < groundRadiusMM) {
                tMin = 0;
                tMax = min(1, atmoDist.y);
            }
            else if (height < atmosphereRadiusMM) {
                float k = (atmosphereRadiusMM - height)/(atmosphereRadiusMM-groundRadiusMM);
                k = k * k;
                k = k * k;
                k = k * k;
                k = k * k;
                tMin = 0;
                tMax = (groundDist.x < 0.0) ? atmoDist.y : min(groundDist.x+1*k, atmoDist.y);
            }
            else {
                tMin = atmoDist.x;
                tMax = (groundDist.x < 0.0) ? atmoDist.y : min(groundDist.x, atmoDist.y);
            }
            raymarchScattering(view_pos, rayDir, sunDir, tMin, tMax, ATMOSPHERE_SAMPLES, lum, transmittance);
        }

        LUT_data = vec4(lum, 1.0);
    }

    /* LUT CLOUDS */
    #if CLOUDS_ENABLE
    if (height < cloudRenderMaxRadiusMM) {
        /* CLOUDS */
        LUT_texcoord = vec2((texcoord.x * LUT_WIDTH) / 256 , (texcoord.y * LUT_HEIGHT - 256) / 256);
        if (LUT_texcoord.x > 0 && LUT_texcoord.x < 1 && LUT_texcoord.y > 0 && LUT_texcoord.y < 1) {
            float u = (LUT_texcoord.x * 256 - 0.5) / 255;
            float v = (LUT_texcoord.y * 256 - 0.5) / 255;
            
            float azimuthAngle = (u - 0.5) * 2.0 * PI;
            
            float coord = 2 * v - 1;
            float altitudeAngle = coord*coord*(sign(coord)*0.5*PI-horizonAngle) + horizonAngle;
            
            float cosAltitude = cos(altitudeAngle);
            vec3 rayDir = vec3(cosAltitude*sin(azimuthAngle), sin(altitudeAngle), -cosAltitude*cos(azimuthAngle));
            
            vec3 sunDir = normalize(view_coord_to_world_coord(sunPosition));
            
            float tMin, tMax;
            vec3 lum=vec3(0.0);
            float transmittance=1.0;
            vec2 atmoDist = rayIntersectSphere(view_pos, rayDir, atmosphereRadiusMM);
            vec2 groundDist = rayIntersectSphere(view_pos, rayDir, groundRadiusMM);
            if (atmoDist.y > 0) {
                    vec2 cloudBottomDist = rayIntersectSphere(view_pos, rayDir, cloudBottomRadiusMM);
                    vec2 cloudTopDist = rayIntersectSphere(view_pos, rayDir, cloudBottomRadiusMM+cloudHeightMM);
                    if (height < cloudBottomRadiusMM) {
                        tMin = cloudBottomDist.y;
                        tMax = cloudTopDist.y;
                    }
                    else if (height < cloudBottomRadiusMM+cloudHeightMM) {
                        tMin = 0;
                        tMax = cloudBottomDist.x > 0 ? cloudBottomDist.x : cloudTopDist.y;
                    }
                    else {
                        tMin = cloudTopDist.x;
                        tMax = cloudBottomDist.x > 0 ? cloudBottomDist.x : cloudTopDist.y;
                    }
                    if ((groundDist.x < 0 || groundDist.x > tMin) && tMax > 0 && tMax > tMin) {
                        raymarchClouds(view_pos, rayDir, sunDir, tMin, tMax, CLOUDS_SAMPLES, lum, transmittance);
                    }
            }
            LUT_data = vec4(lum, transmittance);
        }

        /* ATMOSPHERE */
        LUT_texcoord = vec2((texcoord.x * LUT_WIDTH - 256) / 256, (texcoord.y * LUT_HEIGHT - 256) / 128);
        if (LUT_texcoord.x > 0 && LUT_texcoord.x < 1 && LUT_texcoord.y > 0 && LUT_texcoord.y < 1) {
            float u = (LUT_texcoord.x * 256 - 0.5) / 255;
            float v = (LUT_texcoord.y * 128 - 0.5) / 127;
            
            float azimuthAngle = (u - 0.5) * 2.0 * PI;
            
            float coord = 2 * v - 1;
            float altitudeAngle = coord*coord*(sign(coord)*0.5*PI-horizonAngle) + horizonAngle;
            
            float cosAltitude = cos(altitudeAngle);
            vec3 rayDir = vec3(cosAltitude*sin(azimuthAngle), sin(altitudeAngle), -cosAltitude*cos(azimuthAngle));
            
            vec3 sunDir = normalize(view_coord_to_world_coord(sunPosition));
            
            float tMin, tMax;
            vec3 lum=vec3(0.0), transmittance=vec3(1.0);
            vec2 atmoDist = rayIntersectSphere(view_pos, rayDir, atmosphereRadiusMM);
            vec2 groundDist = rayIntersectSphere(view_pos, rayDir, groundRadiusMM);
            if (atmoDist.y > 0) {
                    vec2 cloudBottomDist = rayIntersectSphere(view_pos, rayDir, cloudBottomRadiusMM);
                    vec2 cloudTopDist = rayIntersectSphere(view_pos, rayDir, cloudBottomRadiusMM+cloudHeightMM);
                    if (height < cloudBottomRadiusMM) {
                        tMin = cloudBottomDist.y;
                        tMax = cloudTopDist.y;
                    }
                    else if (height < cloudBottomRadiusMM+cloudHeightMM) {
                        tMin = 0;
                        tMax = cloudBottomDist.x > 0 ? cloudBottomDist.x : cloudTopDist.y;
                    }
                    else {
                        tMin = cloudTopDist.x;
                        tMax = cloudBottomDist.x > 0 ? cloudBottomDist.x : cloudTopDist.y;
                    }
                    if ((groundDist.x < 0 || groundDist.x > tMin) && tMax > 0 && tMin > 0) {
                        raymarchScattering(view_pos, rayDir, sunDir, 0, tMin, ATMOSPHERE_SAMPLES / 8, lum, transmittance);
                    }
            }
            LUT_data = vec4(lum, 1.0);
        }

        LUT_texcoord = vec2((texcoord.x * LUT_WIDTH - 256) / 256, (texcoord.y * LUT_HEIGHT - 384) / 128);
        if (LUT_texcoord.x > 0 && LUT_texcoord.x < 1 && LUT_texcoord.y > 0 && LUT_texcoord.y < 1) {
            float u = (LUT_texcoord.x * 256 - 0.5) / 255;
            float v = (LUT_texcoord.y * 128 - 0.5) / 127;
            
            float azimuthAngle = (u - 0.5) * 2.0 * PI;
            
            float coord = 2 * v - 1;
            float altitudeAngle = coord*coord*(sign(coord)*0.5*PI-horizonAngle) + horizonAngle;
            
            float cosAltitude = cos(altitudeAngle);
            vec3 rayDir = vec3(cosAltitude*sin(azimuthAngle), sin(altitudeAngle), -cosAltitude*cos(azimuthAngle));
            
            vec3 sunDir = normalize(view_coord_to_world_coord(sunPosition));
            
            float tMin, tMax;
            vec3 lum=vec3(0.0), transmittance=vec3(1.0);
            vec2 atmoDist = rayIntersectSphere(view_pos, rayDir, atmosphereRadiusMM);
            vec2 groundDist = rayIntersectSphere(view_pos, rayDir, groundRadiusMM);
            if (atmoDist.y > 0) {
                    vec2 cloudBottomDist = rayIntersectSphere(view_pos, rayDir, cloudBottomRadiusMM);
                    vec2 cloudTopDist = rayIntersectSphere(view_pos, rayDir, cloudBottomRadiusMM+cloudHeightMM);
                    if (height < cloudBottomRadiusMM) {
                        tMin = cloudBottomDist.y;
                        tMax = cloudTopDist.y;
                    }
                    else if (height < cloudBottomRadiusMM+cloudHeightMM) {
                        tMin = 0;
                        tMax = cloudBottomDist.x > 0 ? cloudBottomDist.x : cloudTopDist.y;
                    }
                    else {
                        tMin = cloudTopDist.x;
                        tMax = cloudBottomDist.x > 0 ? cloudBottomDist.x : cloudTopDist.y;
                    }
                    if ((groundDist.x < 0 || groundDist.x > tMin) && tMax > 0 && tMin > 0) {
                        raymarchScattering(view_pos, rayDir, sunDir, 0, tMin, ATMOSPHERE_SAMPLES / 8, lum, transmittance);
                    }
            }
            LUT_data = vec4(transmittance, 1.0);
        }
    }
    #endif
    
    gl_FragData[0] = LUT_data;
}