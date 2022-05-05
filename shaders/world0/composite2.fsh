#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define GI_TEMPORAL_FILTER_ENABLE 1 // [0 1]
#define GI_TEMPORAL_FILTER_K 0.1 // [0.2 0.1 0.05 0.02 0.01]
#define GI_RES_SCALE 0.5   // [0.25 0.5 1]

#define SSAO_ENABLE 1 // [0 1]
#define SSAO_DISTANCE 256
#define SSAO_SAMPLE_NUM 32   // [1 2 4 8 16 32 64 128 256]
#define SSAO_SAMPLE_RADIUS 0.5   // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SSAO_INTENSITY 1.0   // [0.2 0.4 0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0]

#define SSGI_ENABLE 1 // [0 1]
#define SSGI_STEP_MAX_ITER 18
#define SSGI_DIV_MAX_ITER 10

#define MOON_INTENSITY 2.533e-6
#define SUN_SRAD 2.101e1

#define SKY_ILLUMINATION_INTENSITY 20.0  //[5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]

uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D gaux4;
uniform sampler2D colortex10;
uniform sampler2D colortex12;
uniform sampler2D colortex15;
uniform sampler2D depthtex1;

uniform vec3 sunPosition;
uniform float frameTimeCounter;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

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

vec2 offset(vec2 ori) {
    return vec2(ori.x / viewWidth, ori.y / viewHeight);
}

int is_dist_border(vec2 texcoord) {
    float dist_00 = texture2D(gaux4, texcoord + offset(vec2(-0.5, -0.5))).x;
    float dist_01 = texture2D(gaux4, texcoord + offset(vec2(-0.5,  0.5))).x;
    float dist_10 = texture2D(gaux4, texcoord + offset(vec2( 0.5, -0.5))).x;
    float dist_11 = texture2D(gaux4, texcoord + offset(vec2( 0.5,  0.5))).x;
    float min_ = min(min(dist_00, dist_01), min(dist_10, dist_11));
    float max_ = max(max(dist_00, dist_01), max(dist_10, dist_11));
    return (max_ - min_ > 1e-1) ? 1 : 0;
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

vec3 view_coord_to_screen_coord(vec3 view_coord) {
    vec4 clip_coord = gbufferProjection * vec4(view_coord, 1);
    vec3 ndc_coord = clip_coord.xyz / clip_coord.w;
    vec3 screen_coord = ndc_coord * 0.5 + 0.5;
    return screen_coord;
}

vec3 LUT_sun_color(vec3 sunDir) {
	float sunCosZenithAngle = sunDir.y;
    vec2 uv = vec2((0.5 + 255 * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0)) / viewWidth,
                   3.5 / viewHeight);
    return texture2D(colortex15, uv).rgb;
}

const float groundRadiusMM = 6.360;
const float atmosphereRadiusMM = 6.460;
const vec3 viewPos = vec3(0.0, groundRadiusMM + 0.0001, 0.0);

vec3 LUT_sky(vec3 rayDir) {
    float height = length(viewPos);
    vec3 up = viewPos / height;
    
    float horizonAngle = acos(sqrt(height * height - groundRadiusMM * groundRadiusMM) / height);
    float altitudeAngle = horizonAngle - acos(dot(rayDir, up)); // Between -PI/2 and PI/2
    float azimuthAngle; // Between 0 and 2*PI
    if (abs(altitudeAngle) > (0.5*PI - .0001)) {
        // Looking nearly straight up or down.
        azimuthAngle = 0.0;
    } else {
        vec3 projectedDir = normalize(rayDir - up*(dot(rayDir, up)));
        float sinTheta = projectedDir.x;
        float cosTheta = -projectedDir.z;
        azimuthAngle = atan(sinTheta, cosTheta) + PI;
    }
    
    float v = 0.5 + 0.5*sign(altitudeAngle)*sqrt(abs(altitudeAngle)*2.0/PI);
    vec2 uv = vec2(azimuthAngle / (2.0*PI), v);
    uv.x = (0.5 + uv.x * 255) / viewWidth;
    uv.y = (0.5 + uv.y * 127 + 99) / viewHeight;
    return texture2D(colortex15, uv).rgb;
}

vec3 cal_sun_bloom(vec3 ray_dir, vec3 sun_dir) {
    vec3 color = vec3(0.0);

    const float sun_solid_angle = 2 * PI / 180.0;
    const float min_sun_cos_theta = cos(sun_solid_angle);

    float cos_theta = dot(ray_dir, sun_dir);
    if (cos_theta >= min_sun_cos_theta) {
        color += SUN_SRAD * LUT_sun_color(ray_dir);
    }
    else {
        float offset = min_sun_cos_theta - cos_theta;
        float gaussian_bloom = exp(-offset * 5000.0) * 0.5;
        float inv_bloom = 1.0/(1 + offset * 5000.0) * 0.5;
        color += (gaussian_bloom + inv_bloom) * smoothstep(-0.05, 0.05, sun_dir.y) * LUT_sun_color(ray_dir.y < sun_dir.y ? ray_dir : sun_dir);
    }

    return color;
}

vec3 cal_sky_color(vec3 ray_dir, vec3 sun_dir) {
    vec3 color = LUT_sky(ray_dir);
    color += cal_sun_bloom(ray_dir, sun_dir);
    return color;
}

/* RENDERTARGETS: 0,9 */
void main() {
    vec3 color_s = texture2D(gcolor, texcoord).rgb;
    float block_id_s = texture2D(gnormal, texcoord).a;

    /* SKY */
    if (block_id_s < 0.5) {
        vec3 screen_coord = vec3(texcoord, 1);
        vec3 view_coord = screen_coord_to_view_coord(screen_coord);
        vec3 world_coord = view_coord_to_world_coord(view_coord);
        vec3 ray_dir = normalize(world_coord);
        vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
        color_s = cal_sky_color(ray_dir, sun_dir);
        color_s *= SKY_ILLUMINATION_INTENSITY;
    }

    /* GI */
    vec3 gi = vec3(0.0);
    float ao = 0.0;
#if SSAO_ENABLE || SSGI_ENABLE
    float has_prev = 0;
    vec2 gi_texcoord = (texcoord - 0.5) / GI_RES_SCALE + 0.5;
    if (gi_texcoord.x > 0 && gi_texcoord.x < 1 && gi_texcoord.y > 0 && gi_texcoord.y < 1) {
        vec4 gi_normal_data_s = texture2D(gnormal, gi_texcoord);
        vec3 gi_normal_s = gi_normal_data_s.rgb;
        float gi_block_id_s = gi_normal_data_s.a;
        if (gi_block_id_s > 0.5) {
            vec3 gi_screen_coord = vec3(gi_texcoord, texture2D(depthtex1, gi_texcoord).x);
            vec3 gi_view_coord = screen_coord_to_view_coord(gi_screen_coord);
            #if GI_TEMPORAL_FILTER_ENABLE
                vec4 motion_data = texture2D(colortex12, gi_texcoord);
                vec2 texcoord_prev = motion_data.st;
                has_prev = motion_data.a;
                if (has_prev == 1) {
                    vec4 gi_data = texture2D(colortex10, (texcoord_prev.st - 0.5) * GI_RES_SCALE + 0.5);
                    gi = gi_data.rgb;
                    ao = gi_data.a;
                }
            #endif
            vec3 tangent = normalize(cross(gi_normal_s, gi_normal_s.y < 0.707 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
            vec3 bitangent = cross(gi_normal_s, tangent);
            float y, xz, theta;
            #if SSAO_ENABLE
                /* SSAO */
                float ssao_dist_s = length(gi_view_coord), ao_;
                if (ssao_dist_s < SSAO_DISTANCE) {
                    seed(gi_texcoord);
                    float ssao_sample_depth, r;
                    vec3 ssao_sample;
                    int oc = 0;
                    for (int i = 0; i < SSAO_SAMPLE_NUM; i++) {
                        y = rand();
                        xz = sqrt(1 - y * y);
                        theta = 2 * PI * rand();
                        r = rand();
                        r = r * SSAO_SAMPLE_RADIUS;
                        ssao_sample = r * vec3(xz * cos(theta), y, xz * sin(theta));
                        ssao_sample = SSAO_SAMPLE_RADIUS * (ssao_sample.x * bitangent + ssao_sample.y * gi_normal_s + ssao_sample.z * tangent);
                        ssao_sample += gi_view_coord;
                        ssao_sample = view_coord_to_screen_coord(ssao_sample);
                        ssao_sample_depth = texture2D(depthtex1, ssao_sample.st).x;
                        if (ssao_sample.z > ssao_sample_depth && (ssao_sample.z - ssao_sample_depth) * ssao_dist_s < 0.02 * SSAO_SAMPLE_RADIUS) oc++;
                    }
                    ao_ = 1 - SSAO_INTENSITY * oc / SSAO_SAMPLE_NUM * (1 - smoothstep(SSAO_DISTANCE - 32, SSAO_DISTANCE, ssao_dist_s));
                    ao_ = clamp(ao_, 0, 1);
                    #if GI_TEMPORAL_FILTER_ENABLE
                        if (has_prev == 1) ao = (1 - GI_TEMPORAL_FILTER_K) * ao + GI_TEMPORAL_FILTER_K * ao_;
                        else ao = ao_;
                    #else
                        ao = ao_;
                    #endif
                }
            #endif
            #if SSGI_ENABLE
                /* SSGI */
                seed(gi_texcoord);
                int gi_hit = 0;
                vec2 gi_reflect_texcoord = vec2(0.0);
                y = rand();
                xz = sqrt(1 - y * y);
                theta = 2 * PI * rand();
                vec3 gi_reflect_direction = (xz * cos(theta) * bitangent + y * gi_normal_s + xz * sin(theta) * tangent);
                vec3 gi_reflect_color = vec3(0.0);
                float t = 0, t_step, k, l, h, dist, reflect_dist = texture2D(gaux4, gi_texcoord).x;
                gi_view_coord += 0.01 * gi_normal_s;
                vec3 reflect_coord = gi_view_coord, screen_coord;
                for (int i = 0; i < SSGI_STEP_MAX_ITER; i++) {
                    k = length(gi_reflect_direction - dot(gi_reflect_direction, reflect_coord) / dot(reflect_coord, reflect_coord) * reflect_coord);
                    k = k / reflect_dist;
                    k = k > 0.2 ? 0.2 : k;
                    t_step = 0.05 / k;
                    t_step = t_step > 10 ? 10 : t_step;
                    t_step *= 0.75 + 0.5 * rand();
                    reflect_coord = gi_view_coord + (t + t_step) * gi_reflect_direction;
                    if (reflect_coord.z > 0) break;
                    reflect_dist = length(reflect_coord);
                    screen_coord = view_coord_to_screen_coord(reflect_coord);
                    if (screen_coord.s < 0 || screen_coord.s > 1 || screen_coord.t < 0 || screen_coord.t > 1) {break;}
                    dist = texture2D(gaux4, screen_coord.st).x;
                    if (reflect_dist > dist) {
                        l = 0;
                        h = t_step;
                        for (int j = 0; j < SSGI_DIV_MAX_ITER; j++) {
                            t_step = 0.5 * (l + h);
                            reflect_coord = gi_view_coord + (t + t_step) * gi_reflect_direction;
                            reflect_dist = length(reflect_coord);
                            screen_coord = view_coord_to_screen_coord(reflect_coord);
                            dist = texture2D(gaux4, screen_coord.st).x;
                            if (reflect_dist > dist)  h = t_step;
                            else l = t_step;
                        }
                        if (reflect_dist > dist - 1e-2 && reflect_dist < dist + 1e-2 && is_dist_border(screen_coord.st) == 0) {
                            gi_hit = 1;
                            gi_reflect_texcoord = screen_coord.st;
                        }
                        break;
                    }
                    t += t_step;
                }
                if (gi_hit == 1) {
                    gi_reflect_color = texture2D(gcolor, gi_reflect_texcoord).rgb;
                }
                #if GI_TEMPORAL_FILTER_ENABLE
                    if (has_prev == 1) gi = (1 - GI_TEMPORAL_FILTER_K) * gi + GI_TEMPORAL_FILTER_K * gi_reflect_color;
                    else gi = GI_TEMPORAL_FILTER_K * gi_reflect_color;
                #else
                    gi = gi_reflect_color;
                #endif
            #endif
        }
    }
#endif

    gl_FragData[0] = vec4(color_s, 0.0);
    gl_FragData[1] = vec4(gi, ao);
}