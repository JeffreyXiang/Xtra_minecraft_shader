#version 120

#define PI 3.1415926535898

#define ATMOSPHERE_SAMPLES 32

#define LUT_WIDTH 512
#define LUT_HEIGHT 512

uniform sampler2D colortex15;

uniform vec3 sunPosition;

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

const vec3 viewPos = vec3(0.0, groundRadiusMM + 0.0001, 0.0);

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

/* RENDERTARGETS: 15 */
void main() {
    /* LUT SKY */
    vec4 LUT_data = texture2D(colortex15, texcoord);
    vec2 LUT_texcoord = vec2((texcoord.x * LUT_WIDTH - 256) / 256 , texcoord.y * LUT_HEIGHT / 256);

    if (LUT_texcoord.x > 0 && LUT_texcoord.x < 1 && LUT_texcoord.y > 0 && LUT_texcoord.y < 1) {
        float u = (LUT_texcoord.x * 256 - 0.5) / 255;
        float v = (LUT_texcoord.y * 256 - 0.5) / 255;
        
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
    
    gl_FragData[0] = LUT_data;
}