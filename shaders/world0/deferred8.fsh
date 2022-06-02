#version 120

#define PI 3.1415926535898

#define MOON_INTENSITY 2e-5
#define SUN_SRAD 2e1
#define MOON_SRAD 5e1

#define SKY_ILLUMINATION_INTENSITY 20.0  //[5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]

#define CLOUDS_ENABLE 1 // [0 1]
#define CLOUDS_RES_SCALE 0.5 // [0.25 0.5 1]

#define LUT_WIDTH 512
#define LUT_HEIGHT 512

uniform sampler2D gcolor;
uniform sampler2D gnormal;
#if CLOUDS_ENABLE
uniform sampler2D noisetex;
uniform sampler2D colortex8;
uniform sampler3D colortex14;
#endif
uniform sampler2D colortex15;

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

vec3 LUT_atmosphere_transmittance(vec3 pos, vec3 sunDir) {
    float height = length(pos);
    vec3 up = pos / height;
	float sunCosZenithAngle = dot(sunDir, up);
    vec2 uv = vec2((0.5 + 255 * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0)) / LUT_WIDTH,
                   (3.5 + 63 * clamp((height - groundRadiusMM) / (atmosphereRadiusMM - groundRadiusMM), 0, 1)) / LUT_HEIGHT);
    return texture2D(colortex15, uv).rgb;
}

vec3 LUT_sky(vec3 viewPos, vec3 rayDir) {
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
        (256.5 + u * 255) / LUT_WIDTH,
        (0.5 + v * 255) / LUT_HEIGHT
    )).rgb;
}


vec3 cal_sun_bloom(vec3 view_pos, vec3 ray_dir, vec3 sun_dir) {
    vec3 color = vec3(0.0);

    const float sun_solid_angle = 1 * PI / 180.0;
    const float min_sun_cos_theta = cos(sun_solid_angle);

    float cos_theta = dot(ray_dir, sun_dir);
    if (cos_theta >= min_sun_cos_theta) {
        color += SUN_SRAD * LUT_atmosphere_transmittance(view_pos, ray_dir);
    }
    else {
        float offset = min_sun_cos_theta - cos_theta;
        float gaussian_bloom = exp(-offset * 5000.0) * 0.5;
        float inv_bloom = 1.0/(1 + offset * 5000.0) * 0.5;
        color += (gaussian_bloom + inv_bloom) * smoothstep(-0.05, 0.05, sun_dir.y) * LUT_atmosphere_transmittance(view_pos, ray_dir.y < sun_dir.y ? ray_dir : sun_dir);
    }

    return color;
}

vec3 cal_moon_bloom(vec3 view_pos, vec3 ray_dir, vec3 moon_dir) {
    vec3 color = vec3(0.0);

    const float moon_solid_angle = 1 * PI / 180.0;
    const float min_moon_cos_theta = cos(moon_solid_angle);

    float cos_theta = dot(ray_dir, moon_dir);
    if (cos_theta >= min_moon_cos_theta) {
        color += MOON_SRAD * vec3(MOON_INTENSITY);
    }
    else {
        float offset = min_moon_cos_theta - cos_theta;
        float gaussian_bloom = exp(-offset * 5000.0) * 0.5;
        float inv_bloom = 1.0/(1 + offset * 5000.0) * 0.5;
        color += 10 * (gaussian_bloom + inv_bloom) * smoothstep(-0.05, 0.05, moon_dir.y) * vec3(MOON_INTENSITY);
    }

    return color;
}

vec3 cal_sky_color(vec3 view_pos, vec3 ray_dir, vec3 sun_dir, vec3 moon_dir) {
    vec3 color = LUT_sky(view_pos, ray_dir);
    color += cal_sun_bloom(view_pos, ray_dir, sun_dir);
    color += cal_moon_bloom(view_pos, ray_dir, moon_dir);
    return color;
}

/* RENDERTARGETS: 0 */
void main() {
    vec3 color_s = texture2D(gcolor, texcoord).rgb;
    float block_id_s = texture2D(gnormal, texcoord).a;

    /* SKY */
    vec3 view_pos = viewPos + vec3(0, cameraPosition.y * 1e-6, 0);
    if (block_id_s < 0.5) {
        vec3 screen_coord = vec3(texcoord, 1);
        vec3 view_coord = screen_coord_to_view_coord(screen_coord);
        vec3 world_coord = view_coord_to_world_coord(view_coord);
        vec3 ray_dir = normalize(world_coord);
        vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
        vec3 moon_dir = normalize(view_coord_to_world_coord(moonPosition));
        color_s = cal_sky_color(view_pos, ray_dir, sun_dir, moon_dir);

        #if CLOUDS_ENABLE
        vec4 cloud_data = texture2D(colortex8, texcoord * CLOUDS_RES_SCALE); 
        color_s = color_s * cloud_data.a + cloud_data.rgb;
        #endif

        color_s *= SKY_ILLUMINATION_INTENSITY;
    }

    gl_FragData[0] = vec4(color_s, 0.0);
}