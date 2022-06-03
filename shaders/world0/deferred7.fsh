#version 120

#define PI 3.1415926535898

#define MOON_INTENSITY 2e-5
#define SUN_SRAD 2e1
#define MOON_SRAD 5e1

#define SKY_ILLUMINATION_INTENSITY 20.0  //[5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]

#define CLOUDS_ENABLE 1 // [0 1]
#define CLOUDS_RATIO 0.3 // [0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define CLOUDS_SAMPLES 128
#define CLOUDS_RES_SCALE 0.5 // [0.25 0.5 1]
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
uniform sampler2D gnormal;
uniform sampler2D noisetex;
uniform sampler3D colortex14;
uniform sampler2D colortex15;
#endif

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

varying vec2 texcoord;

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

const float groundRadiusMM = 6.360;
const float atmosphereRadiusMM = 6.460;
const vec3 viewPos = vec3(0.0, groundRadiusMM, 0.0);

#if CLOUDS_ENABLE
//----------------------------------------
float state;

void seed(vec2 screenCoord)
{
	state = screenCoord.x * 12.9898 + screenCoord.y * 78.223 + fract(frameTimeCounter) * 43.7585453;
}

float rand(){
    float val = fract(sin(state) * 43758.5453);
    state = fract(state) * 38.287;
    return val;
}
//----------------------------------------

vec3 LUT_atmosphere_transmittance(vec3 pos, vec3 sunDir) {
    float height = length(pos);
    vec3 up = pos / height;
	float sunCosZenithAngle = dot(sunDir, up);
    vec2 uv = vec2((0.5 + 255 * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0)) / LUT_WIDTH,
                   (3.5 + 63 * clamp((height - groundRadiusMM) / (atmosphereRadiusMM - groundRadiusMM), 0, 1)) / LUT_HEIGHT);
    return texture2D(colortex15, uv).rgb;
}

float LUT_cloud_transmittance(vec3 viewPos, vec3 rayDir) {
    float height = length(viewPos);
    vec3 up = viewPos / height;
    
    float horizonAngle = height > groundRadiusMM ? -asin(sqrt(height * height - groundRadiusMM * groundRadiusMM) / height) : 0;
    float altitudeAngle = asin(dot(rayDir, up)) - horizonAngle; // Between -PI/2 and PI/2
    float azimuthAngle; // Between 0 and 2*PI
    if (abs(rayDir.y) > (1 - 1e-6)) {
        // Looking nearly straight up or down.
        azimuthAngle = 0.0;
    } else {
        vec3 projectedDir = normalize(rayDir - up*(dot(rayDir, up)));
        float sinTheta = projectedDir.x;
        float cosTheta = -projectedDir.z;
        azimuthAngle = atan(sinTheta, cosTheta) + PI;
    }
    float u = azimuthAngle / (2.0*PI);
    float v = 0.5 + 0.5*sign(altitudeAngle)*sqrt(altitudeAngle/(sign(altitudeAngle)*0.5*PI-horizonAngle));
    return texture2D(colortex15, vec2(
        (0.5 + u * 255) / LUT_WIDTH,
        (256.5 + v * 255) / LUT_HEIGHT
    )).a;
}



void LUT_sky_till_clouds(vec3 viewPos, vec3 rayDir, out vec3 lum, out vec3 transmittance) {
    float height = length(viewPos);
    vec3 up = viewPos / height;

    float horizonAngle = height > groundRadiusMM ? -asin(sqrt(height * height - groundRadiusMM * groundRadiusMM) / height) : 0;
    float altitudeAngle = asin(dot(rayDir, up)) - horizonAngle; // Between -PI/2 and PI/2
    float azimuthAngle; // Between 0 and 2*PI
    if (abs(rayDir.y) > (1 - 1e-6)) {
        // Looking nearly straight up or down.
        azimuthAngle = 0.0;
    } else {
        vec3 projectedDir = normalize(rayDir - up*(dot(rayDir, up)));
        float sinTheta = projectedDir.x;
        float cosTheta = -projectedDir.z;
        azimuthAngle = atan(sinTheta, cosTheta) + PI;
    }
    float u = azimuthAngle / (2.0*PI);
    float v = 0.5 + 0.5*sign(altitudeAngle)*sqrt(altitudeAngle/(sign(altitudeAngle)*0.5*PI-horizonAngle));
    lum = texture2D(colortex15, vec2(
        (256.5 + u * 255) / LUT_WIDTH,
        (256.5 + v * 127) / LUT_HEIGHT
    )).rgb;
    transmittance = texture2D(colortex15, vec2(
        (256.5 + u * 255) / LUT_WIDTH,
        (384.5 + v * 127) / LUT_HEIGHT
    )).rgb;
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
        float newT = tMin + ((i + rand())/numSteps) *(tMax - tMin);
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

/* RENDERTARGETS: 8 */
void main() {
    #if CLOUDS_ENABLE
    vec2 tex_coord = texcoord / CLOUDS_RES_SCALE;
    vec4 cloud_data = vec4(0.0, 0.0, 0.0, 1.0);

    if (tex_coord.s < 1 && tex_coord.t < 1) {
        float block_id_s = texture2D(gnormal, tex_coord).a;

        vec3 view_pos = viewPos + vec3(0, cameraPosition.y * 1e-6, 0);
        if (block_id_s < 0.9) {
            vec3 screen_coord = vec3(tex_coord, 1);
            vec3 view_coord = screen_coord_to_view_coord(screen_coord);
            vec3 world_coord = view_coord_to_world_coord(view_coord);
            vec3 ray_dir = normalize(world_coord);
            vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
            float height = length(view_pos);
            if (height < cloudRenderMaxRadiusMM && LUT_cloud_transmittance(view_pos, ray_dir) < 1) {
                seed(tex_coord);      
                float tMin, tMax;
                vec3 lum=vec3(0.0);
                float transmittance=1.0;
                vec2 atmoDist = rayIntersectSphere(view_pos, ray_dir, atmosphereRadiusMM);
                vec2 groundDist = rayIntersectSphere(view_pos, ray_dir, groundRadiusMM);
                if (atmoDist.y > 0) {
                        vec2 cloudBottomDist = rayIntersectSphere(view_pos, ray_dir, cloudBottomRadiusMM);
                        vec2 cloudTopDist = rayIntersectSphere(view_pos, ray_dir, cloudBottomRadiusMM+cloudHeightMM);
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
                            raymarchClouds(view_pos, ray_dir, sun_dir, tMin, tMax, CLOUDS_SAMPLES, lum, transmittance);
                            vec3 atmo_lum, atmo_transmittance;
                            LUT_sky_till_clouds(view_pos, ray_dir, atmo_lum, atmo_transmittance);
                            cloud_data = vec4(atmo_lum * (1 - transmittance) + lum * atmo_transmittance, transmittance);
                        }
                }
            }
        }
    }
    gl_FragData[0] = cloud_data;
    #endif
}