#version 120

#define PI 3.1415926535898

#define GAUSSIAN_KERNEL_SIZE 31
#define GAUSSIAN_KERNEL_STRIDE 1

#define SSAO_ENABLE 1 // [0 1]

#define ATMOSPHERE_SAMPLES 32

uniform sampler2D gcolor;
uniform sampler2D colortex15;

uniform mat4 gbufferModelViewInverse;

uniform float viewWidth;
uniform float viewHeight;
uniform vec3 sunPosition;

varying vec2 texcoord;

vec2 offset(vec2 ori) {
    return vec2(ori.x * GAUSSIAN_KERNEL_STRIDE / viewWidth, ori.y * GAUSSIAN_KERNEL_STRIDE / viewHeight);
}

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
#if SSAO_ENABLE
    vec4 color_data = texture2D(gcolor, texcoord);
    /* SSAO GAUSSIAN HORIZONTAL */

    #if GAUSSIAN_KERNEL_SIZE == 3
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.250000 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.500000 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.250000;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 5
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.062500 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.250000 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.375000 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.250000 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.062500;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 7
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.031250 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.109375 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.218750 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.281250 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.218750 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.109375 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.031250;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 9
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.015625 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.050781 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.117188 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.199219 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.234375 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.199219 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.117188 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.050781 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.015625;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 11
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.008812 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.027144 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.065114 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.121649 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.176998 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.200565 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.176998 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.121649 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.065114 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.027144 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.008812;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 13
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.005799 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.016401 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.038399 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.074414 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.119371 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.158506 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.174219 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.158506 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.119371 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.074414 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.038399 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.016401 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.005799;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 15
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.004107 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.010743 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.024238 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.047162 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.079149 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.114567 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.143029 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.154010 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.143029 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.114567 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.079149 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.047162 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.024238 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.010743 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.004107;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 17
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.003072 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.007494 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.016233 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.031218 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.053308 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.080823 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.108801 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.130045 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.138011 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.130045 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.108801 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.080823 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.053308 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.031218 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.016233 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.007494 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.003072;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 19
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.002395 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.005493 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.011427 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.021558 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.036886 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.057242 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.080567 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.102846 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.119071 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.125029 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.119071 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.102846 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.080567 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.057242 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.036886 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.021558 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.011427 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.005493 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.002395;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 21
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.001929 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.004189 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.008385 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.015466 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.026292 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.041193 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.059478 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.079148 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.097067 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.109711 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.114282 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.109711 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.097067 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.079148 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.059478 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.041193 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.026292 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.015466 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.008385 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.004189 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.001929;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 23
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.001594 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.003299 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.006369 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.011475 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.019289 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.030256 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.044282 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.060474 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.077060 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.091626 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.101656 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.105238 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.101656 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.091626 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.077060 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.060474 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.044282 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.030256 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.019289 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.011475 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.006369 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.003299 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.001594;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 25
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.001346 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.002667 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.004981 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.008765 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.014533 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.022705 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.033424 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.046361 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.060592 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.074617 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.086582 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.094664 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.097521 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.094664 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.086582 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.074617 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.060592 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.046361 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.033424 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.022705 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.014533 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.008765 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.004981 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.002667 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.001346;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 27
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.001156 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.002204 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.003992 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.006867 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.011216 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.017399 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.025632 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.035858 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.047639 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.060105 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.072016 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.081942 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.088544 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.090860 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.088544 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.081942 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.072016 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.060105 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.047639 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.035858 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.025632 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.017399 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.011216 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.006867 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.003992 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.002204 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.001156;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 29
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.001007 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.001855 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.003267 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.005498 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.008844 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.013597 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.019978 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.028055 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.037653 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.048298 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.059210 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.069376 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.077689 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.083148 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.085051 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.083148 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.077689 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.069376 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.059210 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.048298 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.037653 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.028055 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.019978 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.013597 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.008844 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.005498 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.003267 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.001855 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.001007;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 31
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.000888 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.001586 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.002722 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.004487 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.007108 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.010819 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.015820 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.022226 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.030003 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.038911 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.048486 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.058049 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.066772 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.073794 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.078358 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.079940 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.078358 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.073794 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.066772 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.058049 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.048486 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.038911 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.030003 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.022226 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.015820 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.010819 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.007108 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.004487 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.002722 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.001586 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.000888;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 33
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.000791 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.001374 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.002303 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.003724 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.005811 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.008751 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.012717 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.017835 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.024137 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.031524 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.039731 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.048324 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.056720 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.064247 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.070227 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.074079 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.075410 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.074079 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.070227 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.064247 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.056720 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.048324 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.039731 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.031524 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.024137 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.017835 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.012717 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.008751 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.005811 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.003724 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.002303 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.001374 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.000791;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 35
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.000712 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.001205 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.001975 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.003136 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.004822 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.007184 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.010367 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.014489 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.019616 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.025723 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.032673 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.040198 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.047904 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.055296 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.061825 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.066956 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.070236 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.071365 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.070236 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.066956 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.061825 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.055296 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.047904 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.040198 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.032673 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.025723 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.019616 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.014489 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.010367 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.007184 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.004822 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.003136 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.001975 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.001205 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.000712;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 37
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.000645 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.001067 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.001713 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.002674 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.004056 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.005978 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.008561 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.011912 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.016106 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.021160 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.027012 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.033506 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.040385 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.047298 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.053825 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.059518 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.063950 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.066766 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.067732 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.066766 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.063950 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.059518 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.053825 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.047298 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.040385 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.033506 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.027012 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.021160 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.016106 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.011912 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.008561 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.005978 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.004056 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.002674 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.001713 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.001067 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.000645;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 39
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.000589 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.000953 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.001502 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.002307 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.003453 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.005035 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.007154 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.009903 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.013357 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.017552 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.022473 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.028035 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.034075 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.040352 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.046559 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.052342 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.057331 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.061184 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.063618 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.064451 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.063618 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.061184 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.057331 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.052342 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.046559 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.040352 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.034075 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.028035 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.022473 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.017552 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.013357 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.009903 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.007154 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.005035 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.003453 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.002307 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.001502 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.000953 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.000589;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 41
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.000541 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.000858 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.001329 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.002011 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.002971 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.004288 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.006044 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.008320 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.011184 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.014683 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.018825 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.023571 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.028824 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.034423 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.040148 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.045730 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.050869 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.055263 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.058632 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.060751 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.061474 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.060751 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.058632 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.055263 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.050869 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.045730 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.040148 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.034423 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.028824 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.023571 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.018825 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.014683 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.011184 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.008320 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.006044 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.004288 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.002971 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.002011 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.001329 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.000858 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.000541;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 43
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.000499 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.000777 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.001185 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.001768 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.002582 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.003689 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.005158 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.007057 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.009450 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.012383 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.015880 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.019928 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.024473 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.029412 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.034591 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.039812 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.044841 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.049424 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.053310 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.056272 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.058127 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.058759 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.058127 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.056272 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.053310 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.049424 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.044841 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.039812 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.034591 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.029412 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.024473 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.019928 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.015880 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.012383 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.009450 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.007057 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.005158 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.003689 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.002582 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.001768 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.001185 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.000777 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.000499;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 45
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.000463 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.000709 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.001065 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.001568 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.002263 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.003202 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.004442 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.006041 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.008054 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.010527 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.013490 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.016947 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.020871 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.025200 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.029828 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.034613 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.039376 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.043916 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.048016 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.051469 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.054085 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.055719 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.056274 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.055719 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.054085 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.051469 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.048016 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.043916 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.039376 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.034613 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.029828 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.025200 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.020871 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.016947 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.013490 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.010527 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.008054 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.006041 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.004442 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.003202 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.002263 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.001568 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.001065 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.000709 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.000463;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 47
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.000431 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.000650 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.000963 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.001400 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.001999 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.002802 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.003858 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.005214 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.006920 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.009018 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.011539 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.014498 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.017886 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.021666 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.025770 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.030098 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.034516 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.038866 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.042972 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.046653 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.049732 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.052055 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.053500 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.053991 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.053500 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.052055 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.049732 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.046653 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.042972 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.038866 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.034516 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.030098 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.025770 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.021666 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.017886 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.014498 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.011539 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.009018 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.006920 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.005214 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.003858 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.002802 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.001999 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.001400 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.000963 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.000650 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.000431;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 49
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.000403 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.000599 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.000876 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.001259 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.001779 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.002471 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.003376 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.004535 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.005990 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.007780 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.009936 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.012477 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.015405 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.018702 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.022326 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026205 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.030245 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.034323 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.038300 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.042023 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.045337 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.048094 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.050165 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.051450 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.051886 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.051450 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.050165 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.048094 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.045337 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.042023 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.038300 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.034323 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.030245 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026205 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.022326 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.018702 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.015405 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.012477 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.009936 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.007780 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.005990 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.004535 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.003376 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.002471 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.001779 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.001259 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.000876 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.000599 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.000403;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 51
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.000378 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.000555 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.000801 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.001138 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.001593 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.002194 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.002976 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.003973 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.005223 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.006759 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.008611 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.010800 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.013336 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.016213 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.019404 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.022864 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026522 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.030289 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.034055 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.037696 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.041079 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.044071 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.046548 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.048402 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.049550 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.049939 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.049550 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.048402 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.046548 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.044071 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.041079 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.037696 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.034055 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.030289 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026522 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.022864 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.019404 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.016213 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.013336 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.010800 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.008611 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.006759 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.005223 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.003973 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.002976 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.002194 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.001593 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.001138 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.000801 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.000555 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.000378;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 53
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.000356 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.000516 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.000736 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.001035 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.001435 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.001961 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.002640 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.003504 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.004583 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.005909 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.007508 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.009402 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.011605 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.014117 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.016925 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.020000 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.023293 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026738 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.030249 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.033728 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.037065 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.040146 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.042856 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.045089 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.046755 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.047785 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.048133 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.047785 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.046755 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.045089 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.042856 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.040146 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.037065 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.033728 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.030249 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026738 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.023293 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.020000 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.016925 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.014117 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.011605 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.009402 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.007508 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.005909 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.004583 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.003504 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.002640 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.001961 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.001435 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.001035 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.000736 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.000516 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.000356;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 55
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.000336 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.000481 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.000679 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.000946 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.001300 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.001762 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.002356 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.003109 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.004047 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.005197 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.006584 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.008230 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.010149 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.012347 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.014819 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.017548 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.020500 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.023627 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026865 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.030137 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.033354 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.036418 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.039229 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.041690 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.043711 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.045213 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.046140 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.046453 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.046140 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.045213 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.043711 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.041690 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.039229 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.036418 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.033354 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.030137 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026865 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.023627 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.020500 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.017548 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.014819 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.012347 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.010149 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.008230 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.006584 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.005197 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.004047 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.003109 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.002356 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.001762 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.001300 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.000946 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.000679 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.000481 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.000336;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 57
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.000318 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.000450 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.000629 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.000868 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.001183 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.001592 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.002115 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.002774 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.003594 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.004597 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.005806 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.007242 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.008919 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.010847 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.013025 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.015446 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.018086 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.020912 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.023876 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026919 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.029968 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.032944 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.035762 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.038333 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.040574 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.042407 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.043767 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.044603 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.044886 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.044603 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.043767 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.042407 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.040574 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.038333 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.035762 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.032944 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.029968 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026919 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.023876 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.020912 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.018086 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.015446 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.013025 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.010847 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.008919 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.007242 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.005806 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.004597 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.003594 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.002774 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.002115 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.001592 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.001183 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.000868 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.000629 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.000450 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.000318;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 59
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.000302 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.000423 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.000585 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.000801 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.001082 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.001445 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.001908 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.002489 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.003208 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.004088 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.005147 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.006404 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.007875 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.009570 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.011494 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.013641 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.016000 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.018547 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021246 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.024052 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026909 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.029751 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.032508 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.035103 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.037460 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.039505 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.041173 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.042407 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.043166 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.043421 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.043166 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.042407 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.041173 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.039505 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.037460 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.035103 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.032508 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.029751 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026909 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.024052 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021246 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.018547 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.016000 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.013641 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.011494 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.009570 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.007875 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.006404 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.005147 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.004088 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.003208 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.002489 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.001908 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.001445 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.001082 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.000801 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.000585 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.000423 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.000302;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 61
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.000287 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.000398 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.000546 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.000741 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.000994 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.001318 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.001729 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.002244 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.002879 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.003653 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.004585 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.005691 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.006985 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.008480 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.010181 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.012089 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.014196 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.016487 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.018936 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021509 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.024163 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026845 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.029497 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.032053 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.034446 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.036611 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.038482 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.040004 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.041128 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.041817 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.042049 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.041817 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.041128 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.040004 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.038482 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.036611 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.034446 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.032053 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.029497 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026845 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.024163 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021509 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.018936 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.016487 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.014196 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.012089 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.010181 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.008480 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.006985 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.005691 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.004585 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.003653 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.002879 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.002244 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.001729 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.001318 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.000994 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.000741 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.000546 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.000398 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.000287;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 63
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.000274 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.000376 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.000511 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.000688 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.000916 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.001207 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.001574 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.002032 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.002595 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.003280 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.004103 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.005080 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.006223 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.007545 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.009054 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.010751 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.012633 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.014692 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.016910 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019260 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021710 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.024219 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026737 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.029211 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.031583 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.033795 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.035787 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.037504 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.038896 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.039921 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.040550 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.040761 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.040550 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.039921 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.038896 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.037504 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.035787 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.033795 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.031583 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.029211 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026737 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.024219 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021710 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019260 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.016910 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.014692 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.012633 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.010751 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.009054 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.007545 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.006223 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.005080 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.004103 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.003280 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.002595 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.002032 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.001574 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.001207 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.000916 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.000688 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.000511 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.000376 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.000274;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 65
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.000261 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.000356 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.000480 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.000641 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.000848 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.001110 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.001439 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.001848 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.002350 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.002959 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.003689 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.004554 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.005568 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.006740 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.008081 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.009593 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.011277 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.013128 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.015133 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.017274 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019526 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021856 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.024226 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026590 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.028901 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.031106 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.033152 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.034989 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.036567 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.037843 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.038782 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.039357 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.039550 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.039357 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.038782 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.037843 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.036567 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.034989 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.033152 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.031106 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.028901 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026590 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.024226 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021856 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019526 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.017274 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.015133 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.013128 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.011277 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.009593 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.008081 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.006740 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.005568 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.004554 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.003689 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.002959 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.002350 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.001848 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.001439 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.001110 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.000848 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.000641 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.000480 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.000356 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.000261;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 67
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.000250 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.000338 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.000452 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.000599 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.000787 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.001024 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.001321 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.001688 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.002136 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.002679 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.003330 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.004099 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.005001 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.006045 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.007239 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.008589 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.010098 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.011762 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.013574 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.015521 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.017585 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019739 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021953 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.024192 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026413 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.028572 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.030623 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.032520 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.034217 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.035670 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.036843 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.037705 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.038232 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.038409 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.038232 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.037705 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.036843 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.035670 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.034217 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.032520 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.030623 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.028572 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026413 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.024192 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021953 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019739 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.017585 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.015521 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.013574 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.011762 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.010098 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.008589 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.007239 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.006045 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.005001 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.004099 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.003330 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.002679 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.002136 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.001688 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.001321 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.001024 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.000787 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.000599 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.000452 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.000338 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.000250;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 69
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.000240 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.000321 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.000426 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.000562 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.000733 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.000948 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.001216 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.001547 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.001950 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.002436 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.003017 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.003705 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.004509 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.005441 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.006507 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.007716 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.009069 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.010567 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.012205 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.013974 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.015861 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.017846 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019905 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.022008 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.024122 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.026209 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.028228 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.030140 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.031900 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.033470 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.034812 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.035892 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.036685 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.037169 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.037331 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.037169 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.036685 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.035892 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.034812 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.033470 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.031900 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.030140 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.028228 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.026209 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.024122 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.022008 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019905 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.017846 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.015861 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.013974 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.012205 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.010567 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.009069 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.007716 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.006507 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.005441 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.004509 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.003705 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.003017 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.002436 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.001950 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.001547 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.001216 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.000948 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.000733 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.000562 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.000426 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.000321 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.000240;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 71
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.000230 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.000306 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.000403 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.000528 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.000685 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.000881 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.001124 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.001423 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.001786 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.002223 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.002744 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.003360 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.004080 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.004914 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.005870 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.006954 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.008170 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.009519 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.011001 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.012608 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.014331 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.016155 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018062 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.020028 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.022025 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.024021 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.025983 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.027874 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.029657 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.031293 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.032749 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.033989 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.034987 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.035717 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.036163 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.036313 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.036163 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.035717 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.034987 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.033989 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.032749 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.031293 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.029657 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.027874 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.025983 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.024021 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.022025 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.020028 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018062 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.016155 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.014331 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.012608 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.011001 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.009519 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.008170 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.006954 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.005870 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.004914 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.004080 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.003360 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.002744 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.002223 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.001786 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.001423 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.001124 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.000881 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.000685 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.000528 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.000403 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.000306 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.000230;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 73
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.000221 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.000292 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.000382 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.000497 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.000641 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.000821 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.001042 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.001313 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.001641 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.002035 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.002505 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.003058 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.003705 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.004454 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.005312 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.006287 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.007381 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.008599 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.009940 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.011400 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.012972 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.014647 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.016408 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018238 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.020113 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.022009 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.023895 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.025741 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.027513 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.029177 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.030701 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.032052 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.033202 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.034124 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.034799 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.035210 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.035348 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.035210 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.034799 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.034124 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.033202 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.032052 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.030701 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.029177 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.027513 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.025741 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.023895 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.022009 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.020113 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018238 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.016408 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.014647 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.012972 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.011400 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.009940 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.008599 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.007381 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.006287 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.005312 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.004454 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.003705 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.003058 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.002505 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.002035 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.001641 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.001313 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.001042 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.000821 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.000641 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.000497 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.000382 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.000292 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.000221;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 75
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.000213 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.000279 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.000363 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.000469 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.000602 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.000766 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.000969 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.001215 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.001513 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.001870 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.002294 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.002793 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.003376 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.004050 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.004823 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.005701 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.006688 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.007789 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.009004 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.010331 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.011765 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.013300 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.014924 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.016622 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018376 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.020165 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021964 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.023747 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.025484 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.027146 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.028702 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.030122 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.031379 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.032446 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.033301 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.033926 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.034306 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.034434 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.034306 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.033926 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.033301 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.032446 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.031379 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.030122 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.028702 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.027146 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.025484 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.023747 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021964 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.020165 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018376 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.016622 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.014924 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.013300 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.011765 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.010331 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.009004 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.007789 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.006688 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.005701 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.004823 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.004050 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.003376 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.002793 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.002294 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.001870 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.001513 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.001215 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.000969 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.000766 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.000602 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.000469 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.000363 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.000279 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.000213;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 77
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.000205 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.000267 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.000346 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.000444 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.000567 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.000718 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.000903 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.001128 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.001399 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.001723 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.002107 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.002559 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.003085 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.003694 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.004392 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.005185 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.006077 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.007074 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.008176 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.009383 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.010692 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.012099 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.013594 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.015166 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.016801 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018482 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.020187 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021895 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.023580 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.025216 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.026776 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.028233 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.029559 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.030729 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.031722 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.032515 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.033094 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.033447 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.033565 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.033447 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.033094 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.032515 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.031722 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.030729 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.029559 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.028233 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.026776 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.025216 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.023580 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021895 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.020187 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018482 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.016801 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.015166 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.013594 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.012099 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.010692 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.009383 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.008176 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.007074 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.006077 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.005185 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.004392 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.003694 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.003085 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.002559 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.002107 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.001723 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.001399 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.001128 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.000903 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.000718 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.000567 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.000444 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.000346 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.000267 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.000205;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 79
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000198 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.000256 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.000329 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.000421 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.000534 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.000674 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.000844 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.001050 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.001297 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.001592 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.001941 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.002351 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.002828 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.003379 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.004011 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.004729 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.005537 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.006441 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.007442 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.008541 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.009736 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.011025 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.012401 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.013854 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.015375 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.016948 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018557 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.020183 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021804 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.023398 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.024940 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.026406 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.027771 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.029010 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.030102 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.031026 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.031764 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.032303 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.032630 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.032740 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.032630 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.032303 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.031764 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.031026 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.030102 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.029010 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.027771 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.026406 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.024940 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.023398 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021804 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.020183 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018557 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.016948 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.015375 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.013854 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.012401 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.011025 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.009736 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.008541 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.007442 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.006441 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.005537 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.004729 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.004011 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.003379 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.002828 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.002351 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.001941 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.001592 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.001297 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.001050 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.000844 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.000674 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.000534 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.000421 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.000329 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.000256 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000198;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 81
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-40, 0))).w * 0.000191 +
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000246 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.000315 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.000400 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.000505 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.000634 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.000791 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.000980 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.001206 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.001476 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.001794 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.002166 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.002600 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.003100 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.003673 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.004324 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.005059 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.005880 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.006790 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.007792 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.008884 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.010065 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.011330 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.012673 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.014085 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.015553 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.017066 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018606 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.020156 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021695 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.023203 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.024657 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.026036 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.027316 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.028477 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.029497 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.030359 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.031046 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.031547 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.031851 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.031953 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.031851 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.031547 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.031046 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.030359 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.029497 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.028477 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.027316 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.026036 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.024657 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.023203 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021695 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.020156 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018606 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.017066 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.015553 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.014085 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.012673 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.011330 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.010065 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.008884 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.007792 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.006790 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.005880 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.005059 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.004324 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.003673 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.003100 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.002600 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.002166 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.001794 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.001476 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.001206 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.000980 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.000791 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.000634 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.000505 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.000400 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.000315 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000246 +
        texture2D(gcolor, texcoord + offset(vec2(40, 0))).w * 0.000191;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 83
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-41, 0))).w * 0.000185 +
        texture2D(gcolor, texcoord + offset(vec2(-40, 0))).w * 0.000236 +
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000301 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.000381 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.000478 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.000598 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.000742 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.000916 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.001124 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.001371 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.001662 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.002002 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.002397 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.002852 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.003373 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.003965 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.004633 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.005380 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.006210 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.007124 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.008123 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.009206 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.010370 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.011609 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.012918 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.014286 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.015704 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.017157 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018631 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.020108 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021570 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.022997 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.024370 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.025668 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.026870 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.027958 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.028912 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.029717 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.030359 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.030826 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.031109 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.031204 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.031109 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.030826 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.030359 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.029717 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.028912 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.027958 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.026870 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.025668 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.024370 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.022997 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021570 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.020108 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018631 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.017157 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.015704 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.014286 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.012918 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.011609 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.010370 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.009206 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.008123 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.007124 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.006210 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.005380 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.004633 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.003965 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.003373 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.002852 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.002397 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.002002 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.001662 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.001371 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.001124 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.000916 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.000742 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.000598 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.000478 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.000381 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000301 +
        texture2D(gcolor, texcoord + offset(vec2(40, 0))).w * 0.000236 +
        texture2D(gcolor, texcoord + offset(vec2(41, 0))).w * 0.000185;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 85
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-42, 0))).w * 0.000179 +
        texture2D(gcolor, texcoord + offset(vec2(-41, 0))).w * 0.000228 +
        texture2D(gcolor, texcoord + offset(vec2(-40, 0))).w * 0.000288 +
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000363 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.000454 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.000565 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.000699 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.000859 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.001051 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.001277 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.001543 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.001854 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.002215 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.002630 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.003105 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.003645 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.004254 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.004935 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.005693 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.006528 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.007442 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.008436 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.009506 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.010650 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.011862 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.013136 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.014462 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.015829 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.017224 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018634 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.020042 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021431 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.022783 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.024080 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.025303 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.026433 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.027453 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.028348 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.029101 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.029700 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.030136 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.030401 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.030489 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.030401 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.030136 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.029700 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.029101 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.028348 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.027453 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.026433 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.025303 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.024080 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.022783 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021431 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.020042 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018634 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.017224 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.015829 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.014462 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.013136 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.011862 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.010650 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.009506 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.008436 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.007442 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.006528 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.005693 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.004935 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.004254 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.003645 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.003105 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.002630 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.002215 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.001854 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.001543 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.001277 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.001051 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.000859 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.000699 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.000565 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.000454 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000363 +
        texture2D(gcolor, texcoord + offset(vec2(40, 0))).w * 0.000288 +
        texture2D(gcolor, texcoord + offset(vec2(41, 0))).w * 0.000228 +
        texture2D(gcolor, texcoord + offset(vec2(42, 0))).w * 0.000179;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 87
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-43, 0))).w * 0.000173 +
        texture2D(gcolor, texcoord + offset(vec2(-42, 0))).w * 0.000219 +
        texture2D(gcolor, texcoord + offset(vec2(-41, 0))).w * 0.000276 +
        texture2D(gcolor, texcoord + offset(vec2(-40, 0))).w * 0.000346 +
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000431 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.000535 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.000659 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.000807 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.000984 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.001192 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.001437 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.001722 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.002052 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.002432 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.002866 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.003359 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.003915 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.004537 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.005230 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.005994 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.006832 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.007745 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.008730 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.009785 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.010908 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.012092 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.013330 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.014612 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.015930 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.017270 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018618 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019960 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021281 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.022562 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.023788 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.024941 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.026005 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.026963 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.027802 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.028508 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.029069 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.029476 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.029724 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.029807 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.029724 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.029476 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.029069 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.028508 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.027802 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.026963 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.026005 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.024941 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.023788 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.022562 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021281 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019960 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018618 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.017270 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.015930 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.014612 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.013330 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.012092 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.010908 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.009785 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.008730 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.007745 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.006832 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.005994 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.005230 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.004537 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.003915 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.003359 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.002866 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.002432 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.002052 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.001722 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.001437 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.001192 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.000984 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.000807 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.000659 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.000535 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000431 +
        texture2D(gcolor, texcoord + offset(vec2(40, 0))).w * 0.000346 +
        texture2D(gcolor, texcoord + offset(vec2(41, 0))).w * 0.000276 +
        texture2D(gcolor, texcoord + offset(vec2(42, 0))).w * 0.000219 +
        texture2D(gcolor, texcoord + offset(vec2(43, 0))).w * 0.000173;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 89
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-44, 0))).w * 0.000168 +
        texture2D(gcolor, texcoord + offset(vec2(-43, 0))).w * 0.000212 +
        texture2D(gcolor, texcoord + offset(vec2(-42, 0))).w * 0.000265 +
        texture2D(gcolor, texcoord + offset(vec2(-41, 0))).w * 0.000331 +
        texture2D(gcolor, texcoord + offset(vec2(-40, 0))).w * 0.000411 +
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000507 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.000622 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.000760 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.000923 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.001115 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.001340 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.001602 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.001905 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.002254 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.002651 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.003102 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.003611 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.004181 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.004815 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.005516 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.006285 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.007123 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.008030 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.009005 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.010044 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.011144 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.012298 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.013500 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.014741 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.016010 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.017295 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018585 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019865 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.021120 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.022336 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.023495 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.024584 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.025586 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.026488 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.027275 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.027937 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.028463 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.028845 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.029076 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.029154 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.029076 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.028845 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.028463 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.027937 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.027275 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.026488 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.025586 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.024584 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.023495 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.022336 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.021120 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019865 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018585 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.017295 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.016010 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.014741 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.013500 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.012298 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.011144 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.010044 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.009005 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.008030 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.007123 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.006285 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.005516 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.004815 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.004181 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.003611 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.003102 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.002651 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.002254 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.001905 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.001602 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.001340 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.001115 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.000923 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.000760 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.000622 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000507 +
        texture2D(gcolor, texcoord + offset(vec2(40, 0))).w * 0.000411 +
        texture2D(gcolor, texcoord + offset(vec2(41, 0))).w * 0.000331 +
        texture2D(gcolor, texcoord + offset(vec2(42, 0))).w * 0.000265 +
        texture2D(gcolor, texcoord + offset(vec2(43, 0))).w * 0.000212 +
        texture2D(gcolor, texcoord + offset(vec2(44, 0))).w * 0.000168;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 91
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-45, 0))).w * 0.000163 +
        texture2D(gcolor, texcoord + offset(vec2(-44, 0))).w * 0.000204 +
        texture2D(gcolor, texcoord + offset(vec2(-43, 0))).w * 0.000255 +
        texture2D(gcolor, texcoord + offset(vec2(-42, 0))).w * 0.000317 +
        texture2D(gcolor, texcoord + offset(vec2(-41, 0))).w * 0.000392 +
        texture2D(gcolor, texcoord + offset(vec2(-40, 0))).w * 0.000482 +
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000589 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.000717 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.000868 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.001046 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.001253 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.001495 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.001773 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.002093 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.002458 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.002872 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.003338 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.003861 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.004443 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.005086 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.005792 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.006563 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.007400 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.008300 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.009262 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.010283 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.011359 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.012483 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.013649 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.014848 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.016070 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.017304 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018537 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019758 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.020952 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.022105 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.023203 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.024231 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.025177 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.026025 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.026766 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.027388 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.027881 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.028239 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.028456 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.028529 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.028456 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.028239 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.027881 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.027388 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.026766 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.026025 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.025177 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.024231 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.023203 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.022105 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.020952 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019758 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018537 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.017304 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.016070 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.014848 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.013649 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.012483 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.011359 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.010283 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.009262 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.008300 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.007400 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.006563 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.005792 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.005086 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.004443 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.003861 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.003338 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.002872 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.002458 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.002093 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.001773 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.001495 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.001253 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.001046 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.000868 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.000717 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000589 +
        texture2D(gcolor, texcoord + offset(vec2(40, 0))).w * 0.000482 +
        texture2D(gcolor, texcoord + offset(vec2(41, 0))).w * 0.000392 +
        texture2D(gcolor, texcoord + offset(vec2(42, 0))).w * 0.000317 +
        texture2D(gcolor, texcoord + offset(vec2(43, 0))).w * 0.000255 +
        texture2D(gcolor, texcoord + offset(vec2(44, 0))).w * 0.000204 +
        texture2D(gcolor, texcoord + offset(vec2(45, 0))).w * 0.000163;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 93
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-46, 0))).w * 0.000158 +
        texture2D(gcolor, texcoord + offset(vec2(-45, 0))).w * 0.000198 +
        texture2D(gcolor, texcoord + offset(vec2(-44, 0))).w * 0.000246 +
        texture2D(gcolor, texcoord + offset(vec2(-43, 0))).w * 0.000304 +
        texture2D(gcolor, texcoord + offset(vec2(-42, 0))).w * 0.000374 +
        texture2D(gcolor, texcoord + offset(vec2(-41, 0))).w * 0.000458 +
        texture2D(gcolor, texcoord + offset(vec2(-40, 0))).w * 0.000559 +
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000678 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.000818 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.000983 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.001175 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.001397 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.001654 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.001948 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.002284 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.002664 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.003093 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.003573 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.004107 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.004698 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.005348 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.006059 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.006830 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.007662 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.008553 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.009501 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.010503 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.011554 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.012648 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.013778 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.014936 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.016112 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.017296 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018476 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019641 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.020777 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.021872 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.022912 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.023884 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.024776 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.025577 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.026274 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.026858 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.027322 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.027658 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.027862 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.027930 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.027862 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.027658 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.027322 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.026858 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.026274 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.025577 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.024776 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.023884 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.022912 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.021872 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.020777 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019641 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018476 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.017296 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.016112 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.014936 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.013778 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.012648 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.011554 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.010503 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.009501 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.008553 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.007662 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.006830 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.006059 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.005348 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.004698 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.004107 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.003573 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.003093 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.002664 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.002284 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.001948 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.001654 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.001397 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.001175 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.000983 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.000818 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000678 +
        texture2D(gcolor, texcoord + offset(vec2(40, 0))).w * 0.000559 +
        texture2D(gcolor, texcoord + offset(vec2(41, 0))).w * 0.000458 +
        texture2D(gcolor, texcoord + offset(vec2(42, 0))).w * 0.000374 +
        texture2D(gcolor, texcoord + offset(vec2(43, 0))).w * 0.000304 +
        texture2D(gcolor, texcoord + offset(vec2(44, 0))).w * 0.000246 +
        texture2D(gcolor, texcoord + offset(vec2(45, 0))).w * 0.000198 +
        texture2D(gcolor, texcoord + offset(vec2(46, 0))).w * 0.000158;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 95
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-47, 0))).w * 0.000154 +
        texture2D(gcolor, texcoord + offset(vec2(-46, 0))).w * 0.000191 +
        texture2D(gcolor, texcoord + offset(vec2(-45, 0))).w * 0.000237 +
        texture2D(gcolor, texcoord + offset(vec2(-44, 0))).w * 0.000292 +
        texture2D(gcolor, texcoord + offset(vec2(-43, 0))).w * 0.000358 +
        texture2D(gcolor, texcoord + offset(vec2(-42, 0))).w * 0.000437 +
        texture2D(gcolor, texcoord + offset(vec2(-41, 0))).w * 0.000530 +
        texture2D(gcolor, texcoord + offset(vec2(-40, 0))).w * 0.000641 +
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000772 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.000925 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.001103 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.001309 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.001546 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.001817 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.002127 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.002477 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.002871 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.003313 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.003805 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.004349 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.004948 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.005603 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.006315 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.007084 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.007910 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.008790 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.009723 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.010705 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.011730 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.012794 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.013888 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.015006 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.016138 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.017274 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018403 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019515 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.020596 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.021636 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.022622 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.023543 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.024386 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.025141 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.025798 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.026348 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.026784 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.027100 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.027292 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.027356 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.027292 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.027100 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.026784 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.026348 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.025798 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.025141 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.024386 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.023543 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.022622 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.021636 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.020596 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019515 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018403 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.017274 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.016138 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.015006 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.013888 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.012794 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.011730 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.010705 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.009723 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.008790 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.007910 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.007084 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.006315 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.005603 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.004948 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.004349 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.003805 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.003313 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.002871 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.002477 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.002127 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.001817 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.001546 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.001309 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.001103 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.000925 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000772 +
        texture2D(gcolor, texcoord + offset(vec2(40, 0))).w * 0.000641 +
        texture2D(gcolor, texcoord + offset(vec2(41, 0))).w * 0.000530 +
        texture2D(gcolor, texcoord + offset(vec2(42, 0))).w * 0.000437 +
        texture2D(gcolor, texcoord + offset(vec2(43, 0))).w * 0.000358 +
        texture2D(gcolor, texcoord + offset(vec2(44, 0))).w * 0.000292 +
        texture2D(gcolor, texcoord + offset(vec2(45, 0))).w * 0.000237 +
        texture2D(gcolor, texcoord + offset(vec2(46, 0))).w * 0.000191 +
        texture2D(gcolor, texcoord + offset(vec2(47, 0))).w * 0.000154;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 97
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-48, 0))).w * 0.000150 +
        texture2D(gcolor, texcoord + offset(vec2(-47, 0))).w * 0.000185 +
        texture2D(gcolor, texcoord + offset(vec2(-46, 0))).w * 0.000228 +
        texture2D(gcolor, texcoord + offset(vec2(-45, 0))).w * 0.000280 +
        texture2D(gcolor, texcoord + offset(vec2(-44, 0))).w * 0.000342 +
        texture2D(gcolor, texcoord + offset(vec2(-43, 0))).w * 0.000417 +
        texture2D(gcolor, texcoord + offset(vec2(-42, 0))).w * 0.000504 +
        texture2D(gcolor, texcoord + offset(vec2(-41, 0))).w * 0.000608 +
        texture2D(gcolor, texcoord + offset(vec2(-40, 0))).w * 0.000730 +
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000872 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.001037 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.001228 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.001447 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.001698 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.001984 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.002307 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.002671 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.003078 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.003531 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.004033 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.004586 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.005190 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.005848 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.006560 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.007325 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.008143 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.009012 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.009928 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.010889 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.011888 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.012921 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.013981 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.015060 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.016149 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.017239 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018320 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019381 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.020411 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.021400 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.022335 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.023207 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.024004 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.024717 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.025337 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.025856 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.026267 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.026565 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.026745 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.026805 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.026745 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.026565 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.026267 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.025856 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.025337 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.024717 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.024004 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.023207 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.022335 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.021400 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.020411 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019381 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018320 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.017239 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.016149 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.015060 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.013981 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.012921 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.011888 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.010889 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.009928 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.009012 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.008143 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.007325 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.006560 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.005848 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.005190 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.004586 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.004033 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.003531 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.003078 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.002671 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.002307 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.001984 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.001698 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.001447 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.001228 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.001037 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000872 +
        texture2D(gcolor, texcoord + offset(vec2(40, 0))).w * 0.000730 +
        texture2D(gcolor, texcoord + offset(vec2(41, 0))).w * 0.000608 +
        texture2D(gcolor, texcoord + offset(vec2(42, 0))).w * 0.000504 +
        texture2D(gcolor, texcoord + offset(vec2(43, 0))).w * 0.000417 +
        texture2D(gcolor, texcoord + offset(vec2(44, 0))).w * 0.000342 +
        texture2D(gcolor, texcoord + offset(vec2(45, 0))).w * 0.000280 +
        texture2D(gcolor, texcoord + offset(vec2(46, 0))).w * 0.000228 +
        texture2D(gcolor, texcoord + offset(vec2(47, 0))).w * 0.000185 +
        texture2D(gcolor, texcoord + offset(vec2(48, 0))).w * 0.000150;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 99
    float ao =
        texture2D(gcolor, texcoord + offset(vec2(-49, 0))).w * 0.000146 +
        texture2D(gcolor, texcoord + offset(vec2(-48, 0))).w * 0.000180 +
        texture2D(gcolor, texcoord + offset(vec2(-47, 0))).w * 0.000220 +
        texture2D(gcolor, texcoord + offset(vec2(-46, 0))).w * 0.000270 +
        texture2D(gcolor, texcoord + offset(vec2(-45, 0))).w * 0.000328 +
        texture2D(gcolor, texcoord + offset(vec2(-44, 0))).w * 0.000398 +
        texture2D(gcolor, texcoord + offset(vec2(-43, 0))).w * 0.000481 +
        texture2D(gcolor, texcoord + offset(vec2(-42, 0))).w * 0.000578 +
        texture2D(gcolor, texcoord + offset(vec2(-41, 0))).w * 0.000691 +
        texture2D(gcolor, texcoord + offset(vec2(-40, 0))).w * 0.000824 +
        texture2D(gcolor, texcoord + offset(vec2(-39, 0))).w * 0.000977 +
        texture2D(gcolor, texcoord + offset(vec2(-38, 0))).w * 0.001154 +
        texture2D(gcolor, texcoord + offset(vec2(-37, 0))).w * 0.001358 +
        texture2D(gcolor, texcoord + offset(vec2(-36, 0))).w * 0.001590 +
        texture2D(gcolor, texcoord + offset(vec2(-35, 0))).w * 0.001854 +
        texture2D(gcolor, texcoord + offset(vec2(-34, 0))).w * 0.002153 +
        texture2D(gcolor, texcoord + offset(vec2(-33, 0))).w * 0.002489 +
        texture2D(gcolor, texcoord + offset(vec2(-32, 0))).w * 0.002865 +
        texture2D(gcolor, texcoord + offset(vec2(-31, 0))).w * 0.003284 +
        texture2D(gcolor, texcoord + offset(vec2(-30, 0))).w * 0.003747 +
        texture2D(gcolor, texcoord + offset(vec2(-29, 0))).w * 0.004257 +
        texture2D(gcolor, texcoord + offset(vec2(-28, 0))).w * 0.004816 +
        texture2D(gcolor, texcoord + offset(vec2(-27, 0))).w * 0.005425 +
        texture2D(gcolor, texcoord + offset(vec2(-26, 0))).w * 0.006084 +
        texture2D(gcolor, texcoord + offset(vec2(-25, 0))).w * 0.006794 +
        texture2D(gcolor, texcoord + offset(vec2(-24, 0))).w * 0.007554 +
        texture2D(gcolor, texcoord + offset(vec2(-23, 0))).w * 0.008363 +
        texture2D(gcolor, texcoord + offset(vec2(-22, 0))).w * 0.009218 +
        texture2D(gcolor, texcoord + offset(vec2(-21, 0))).w * 0.010118 +
        texture2D(gcolor, texcoord + offset(vec2(-20, 0))).w * 0.011056 +
        texture2D(gcolor, texcoord + offset(vec2(-19, 0))).w * 0.012030 +
        texture2D(gcolor, texcoord + offset(vec2(-18, 0))).w * 0.013033 +
        texture2D(gcolor, texcoord + offset(vec2(-17, 0))).w * 0.014058 +
        texture2D(gcolor, texcoord + offset(vec2(-16, 0))).w * 0.015099 +
        texture2D(gcolor, texcoord + offset(vec2(-15, 0))).w * 0.016147 +
        texture2D(gcolor, texcoord + offset(vec2(-14, 0))).w * 0.017193 +
        texture2D(gcolor, texcoord + offset(vec2(-13, 0))).w * 0.018227 +
        texture2D(gcolor, texcoord + offset(vec2(-12, 0))).w * 0.019240 +
        texture2D(gcolor, texcoord + offset(vec2(-11, 0))).w * 0.020222 +
        texture2D(gcolor, texcoord + offset(vec2(-10, 0))).w * 0.021163 +
        texture2D(gcolor, texcoord + offset(vec2(-9, 0))).w * 0.022051 +
        texture2D(gcolor, texcoord + offset(vec2(-8, 0))).w * 0.022877 +
        texture2D(gcolor, texcoord + offset(vec2(-7, 0))).w * 0.023632 +
        texture2D(gcolor, texcoord + offset(vec2(-6, 0))).w * 0.024306 +
        texture2D(gcolor, texcoord + offset(vec2(-5, 0))).w * 0.024892 +
        texture2D(gcolor, texcoord + offset(vec2(-4, 0))).w * 0.025382 +
        texture2D(gcolor, texcoord + offset(vec2(-3, 0))).w * 0.025769 +
        texture2D(gcolor, texcoord + offset(vec2(-2, 0))).w * 0.026049 +
        texture2D(gcolor, texcoord + offset(vec2(-1, 0))).w * 0.026219 +
        texture2D(gcolor, texcoord + offset(vec2(0, 0))).w * 0.026276 +
        texture2D(gcolor, texcoord + offset(vec2(1, 0))).w * 0.026219 +
        texture2D(gcolor, texcoord + offset(vec2(2, 0))).w * 0.026049 +
        texture2D(gcolor, texcoord + offset(vec2(3, 0))).w * 0.025769 +
        texture2D(gcolor, texcoord + offset(vec2(4, 0))).w * 0.025382 +
        texture2D(gcolor, texcoord + offset(vec2(5, 0))).w * 0.024892 +
        texture2D(gcolor, texcoord + offset(vec2(6, 0))).w * 0.024306 +
        texture2D(gcolor, texcoord + offset(vec2(7, 0))).w * 0.023632 +
        texture2D(gcolor, texcoord + offset(vec2(8, 0))).w * 0.022877 +
        texture2D(gcolor, texcoord + offset(vec2(9, 0))).w * 0.022051 +
        texture2D(gcolor, texcoord + offset(vec2(10, 0))).w * 0.021163 +
        texture2D(gcolor, texcoord + offset(vec2(11, 0))).w * 0.020222 +
        texture2D(gcolor, texcoord + offset(vec2(12, 0))).w * 0.019240 +
        texture2D(gcolor, texcoord + offset(vec2(13, 0))).w * 0.018227 +
        texture2D(gcolor, texcoord + offset(vec2(14, 0))).w * 0.017193 +
        texture2D(gcolor, texcoord + offset(vec2(15, 0))).w * 0.016147 +
        texture2D(gcolor, texcoord + offset(vec2(16, 0))).w * 0.015099 +
        texture2D(gcolor, texcoord + offset(vec2(17, 0))).w * 0.014058 +
        texture2D(gcolor, texcoord + offset(vec2(18, 0))).w * 0.013033 +
        texture2D(gcolor, texcoord + offset(vec2(19, 0))).w * 0.012030 +
        texture2D(gcolor, texcoord + offset(vec2(20, 0))).w * 0.011056 +
        texture2D(gcolor, texcoord + offset(vec2(21, 0))).w * 0.010118 +
        texture2D(gcolor, texcoord + offset(vec2(22, 0))).w * 0.009218 +
        texture2D(gcolor, texcoord + offset(vec2(23, 0))).w * 0.008363 +
        texture2D(gcolor, texcoord + offset(vec2(24, 0))).w * 0.007554 +
        texture2D(gcolor, texcoord + offset(vec2(25, 0))).w * 0.006794 +
        texture2D(gcolor, texcoord + offset(vec2(26, 0))).w * 0.006084 +
        texture2D(gcolor, texcoord + offset(vec2(27, 0))).w * 0.005425 +
        texture2D(gcolor, texcoord + offset(vec2(28, 0))).w * 0.004816 +
        texture2D(gcolor, texcoord + offset(vec2(29, 0))).w * 0.004257 +
        texture2D(gcolor, texcoord + offset(vec2(30, 0))).w * 0.003747 +
        texture2D(gcolor, texcoord + offset(vec2(31, 0))).w * 0.003284 +
        texture2D(gcolor, texcoord + offset(vec2(32, 0))).w * 0.002865 +
        texture2D(gcolor, texcoord + offset(vec2(33, 0))).w * 0.002489 +
        texture2D(gcolor, texcoord + offset(vec2(34, 0))).w * 0.002153 +
        texture2D(gcolor, texcoord + offset(vec2(35, 0))).w * 0.001854 +
        texture2D(gcolor, texcoord + offset(vec2(36, 0))).w * 0.001590 +
        texture2D(gcolor, texcoord + offset(vec2(37, 0))).w * 0.001358 +
        texture2D(gcolor, texcoord + offset(vec2(38, 0))).w * 0.001154 +
        texture2D(gcolor, texcoord + offset(vec2(39, 0))).w * 0.000977 +
        texture2D(gcolor, texcoord + offset(vec2(40, 0))).w * 0.000824 +
        texture2D(gcolor, texcoord + offset(vec2(41, 0))).w * 0.000691 +
        texture2D(gcolor, texcoord + offset(vec2(42, 0))).w * 0.000578 +
        texture2D(gcolor, texcoord + offset(vec2(43, 0))).w * 0.000481 +
        texture2D(gcolor, texcoord + offset(vec2(44, 0))).w * 0.000398 +
        texture2D(gcolor, texcoord + offset(vec2(45, 0))).w * 0.000328 +
        texture2D(gcolor, texcoord + offset(vec2(46, 0))).w * 0.000270 +
        texture2D(gcolor, texcoord + offset(vec2(47, 0))).w * 0.000220 +
        texture2D(gcolor, texcoord + offset(vec2(48, 0))).w * 0.000180 +
        texture2D(gcolor, texcoord + offset(vec2(49, 0))).w * 0.000146;
    #endif
    
    color_data.w = ao;
    gl_FragData[0] = color_data;
#endif

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