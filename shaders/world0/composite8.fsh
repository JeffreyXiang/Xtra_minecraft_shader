#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SKY_ILLUMINATION_INTENSITY 3.0  //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]

#define SSR_STEP_MAX_ITER 100
#define SSR_DIV_MAX_ITER 8
#define SSR_F0 0.04
#define SSR_ETA 1.05

#define FOG_AIR_DECAY 0.001     //[0.0001 0.0002 0.0005 0.001 0.002 0.005 0.01 0.02 0.05]
#define FOG_THICKNESS 256
#define FOG_WATER_DECAY 0.1     //[0.01 0.02 0.05 0.1 0.2 0.5 1.0]

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D gdepth;
uniform sampler2D composite;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D colortex8;
uniform sampler2D colortex15;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D noisetex;

uniform int isEyeInWater;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform vec3 sunPosition;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform ivec2 eyeBrightnessSmooth;

varying vec2 texcoord;

//----------------------------------------
float state;

void seed(vec2 screenCoord)
{
	state = screenCoord.x * 12.9898 + screenCoord.y * 78.223;
    // state *= (1 + fract(sin(state + frameTimeCounter) * 43758.5453));
}

float rand(){
    float val = fract(sin(state) * 43758.5453);
    state = val * 38.287 + 4.3783;
    return val;
}
//----------------------------------------

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

vec3 view_coord_to_screen_coord(vec3 view_coord) {
    vec4 clid_coord = gbufferProjection * vec4(view_coord, 1);
    vec3 ndc_coord = clid_coord.xyz / clid_coord.w;
    vec3 screen_coord = ndc_coord * 0.5 + 0.5;
    return screen_coord;
}

float grayscale(vec3 color) {
    return color.r * 0.299 + color.g * 0.587 + color.b * 0.114;
}

float wave(float x) {
    return 0.02 * sin(3 * x + 5 * frameTimeCounter) + 0.01 * sin(5 * x + 5 * frameTimeCounter) + 0.008 * sin(7 * x + 5 * frameTimeCounter) + 0.005 * sin(11 * x + 5 * frameTimeCounter);
}

vec2 nearest(vec2 texcoord) {
    return vec2((floor(texcoord.s * viewWidth) + 0.5) / viewWidth, (floor(texcoord.t * viewHeight) + 0.5) / viewHeight);
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

vec3 LUT_water_scattering(float decay) {
    return texture2D(colortex15, vec2((0.5 + (1 - decay) * 255) / viewWidth, 2.5 / viewHeight)).rgb;
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

vec3 cal_water_color(float self_lum, float target_lum, float y_diff, float decay) {
    float cutoff = target_lum < 1e-3 ? abs((target_lum - self_lum) * 15 / y_diff) + 1e-3 : 1;
    cutoff = cutoff > 1 ? 1 : cutoff;
    float max_ = -log(decay);
    vec3 res = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        float k = -log(1 - (i + 0.5) / 8 * (1 - decay)) / max_ / cutoff;
        k = self_lum > target_lum ? (k > 1 ? 1 : k) : (k - (1 / cutoff) < -1 ? 0 : k - (1 / cutoff) + 1);
        res += (1 - (i + 0.5) / 8 * (1 - decay)) * LUT_water_scattering(mix(self_lum, target_lum, k));
    }
    res = res / 8 * (1 - decay);
    return res;
}

vec3 cal_sun_bloom(vec3 ray_dir, vec3 sun_dir) {
    vec3 color = vec3(0.0);
        
    const float sun_solid_angle = 2 * PI / 180.0;
    const float min_sun_cos_theta = cos(sun_solid_angle);

    float cos_theta = dot(ray_dir, sun_dir);
    if (cos_theta >= min_sun_cos_theta) {
        color += 5 * LUT_sun_color(ray_dir);
    }
    else {
        float offset = min_sun_cos_theta - cos_theta;
        float gaussian_bloom = exp(-offset * 5000.0) * 0.5;
        float inv_bloom = 1.0/(1 + offset * 5000.0) * 0.5;
        color += (gaussian_bloom + inv_bloom) * smoothstep(-0.05, 0.05, sun_dir.y) * LUT_sun_color(ray_dir);
    }

    return color;
}

/* DRAWBUFFERS: 08 */
void main() {
    vec4 color_data = texture2D(gcolor, texcoord);
    vec3 color = color_data.rgb;
    float alpha = color_data.a;
    float depth0 = texture2D(depthtex0, texcoord).x;
    float depth1 = texture2D(depthtex0, texcoord).x;
    vec4 dist_data = texture2D(gdepth, texcoord);
    float dist0 = dist_data.x;
    float dist1 = dist_data.y;
    vec3 screen_coord = vec3(texcoord, depth0);
    vec3 view_coord = screen_coord_to_view_coord(screen_coord);
    vec4 data = texture2D(gaux1, texcoord);
    vec3 normal = data.xyz;
    float block_id1 = data.w;
    float block_id0 = texture2D(gnormal, texcoord).w;
    vec4 lumi_data = texture2D(gaux2, texcoord);
    vec3 bloom = texture2D(colortex8, texcoord).rgb;

    int is_water_out = (isEyeInWater == 0 && block_id1 > 1.5) ? 1 : 0;
    int is_water_in = (isEyeInWater == 1) ? 1 : 0;
    if (block_id1 > 0.5 || is_water_in == 1) {
        vec3 direction;

        /* WATER */
        float water_depth;
        if (block_id1 > 1.5) {
            vec3 world_coord = view_coord_to_world_coord(view_coord) + cameraPosition;
            vec2 d0 = vec2(0.4472, 0.8944);
            vec2 d1 = vec2(0.8944, 0.4472);
            vec2 d0T = vec2(-d0.y, d0.x);
            vec2 d1T = vec2(-d1.y, d1.x);
            vec3 offset = vec3(
                d0T * wave(dot(d0, world_coord.xz)) + d1T * wave(dot(d1, world_coord.xz)),
            0);
            vec2 nd0 = vec2(-0.0806,  0.1613);
            vec2 nd1 = vec2(-0.0602, -0.1844);
            vec2 nd2 = vec2( 0.1758,  0.1074);
            vec2 nd3 = vec2(-0.0480, -0.0813);
            vec2 nd4 = vec2( 0.2454,  0.2085);
            vec2 nd5 = vec2( 0.0343, -0.3817);
            offset += 0.02 * (
                texture2D(noisetex, fract((world_coord.xz + frameTimeCounter * 3 * nd0) / 128)).rgb +
                texture2D(noisetex, fract((world_coord.xz + frameTimeCounter * 3 * nd1) / 128)).rgb +
                texture2D(noisetex, fract((world_coord.xz + frameTimeCounter * 3 * nd2) / 128)).rgb +
                texture2D(noisetex, fract((world_coord.xz + frameTimeCounter * 3 * nd3) / 128)).rgb +
                texture2D(noisetex, fract((world_coord.xz + frameTimeCounter * 3 * nd4) / 128)).rgb +
                texture2D(noisetex, fract((world_coord.xz + frameTimeCounter * 3 * nd5) / 128)).rgb - 3);
            vec3 old_normal = normal;
            normal += 2 * offset;
            normal = normalize(normal);
            direction = reflect(normalize(view_coord), normal);
            if (dot(direction, old_normal) < 0) direction = normalize(direction - 2 * dot(direction, old_normal) * old_normal);
            water_depth = dist1 - dist0;
            water_depth = water_depth < 0 ? 0 : water_depth;
            vec2 tex_coord = texcoord - 0.3 * water_depth / dist1 * offset.xy;
            if (texture2D(gaux1, tex_coord).w > 1.5) {
                color_data = texture2D(gcolor, tex_coord);
                color = color_data.rgb;
                alpha = color_data.a;
                dist_data = texture2D(gdepth, tex_coord);
                dist1 = dist_data.y;
                water_depth = dist1 - dist0;
                water_depth = water_depth < 0 ? 0 : water_depth;
            }
        }
        else {
            direction = reflect(normalize(view_coord), normal);
        }

        /* SSR */
        if (isEyeInWater == 0 && block_id1 > 0.5 || isEyeInWater == 1 && block_id1 > 1.5) {
            seed(texcoord);
            float t = 0, t_oc = 0, t_step, t_in, k, k_in, l, h, dist, dist_in, reflect_dist, f_r;
            if (isEyeInWater == 0) f_r = 1 - dot(direction, normal);
            else {
                float sin_t = SSR_ETA * length(cross(direction, normal));
                sin_t = sin_t > 1 ? 1 : sin_t;
                f_r = 1 - sqrt(1 - sin_t * sin_t);
            }
            vec3 reflect_color = vec3(0.0), reflect_coord = view_coord;
            reflect_dist = length(reflect_coord);
            int i, flag = 1, hit = 0;
            f_r = SSR_F0 + (1 - SSR_F0) * f_r * f_r * f_r * f_r * f_r;
            for (i = 0; i < SSR_STEP_MAX_ITER; i++) {
                k = length((direction - dot(direction, reflect_coord) / dot(reflect_coord, reflect_coord) * reflect_coord).xy);
                t_step = 0.001 * -view_coord.z / k * (reflect_dist + 10);
                t_step = t_step > 2 ? 2 : t_step;
                t_step *= 0.75 + 0.5 * rand();
                reflect_coord = view_coord + (t + t_step) * direction;
                if (reflect_coord.z > 0) {
                    t_oc = 0;
                    flag = 1;
                    break;
                }
                reflect_dist = length(reflect_coord);
                screen_coord = view_coord_to_screen_coord(reflect_coord);
                dist = texture2D(gdepth, screen_coord.st).x;
                if (screen_coord.s < 0 || screen_coord.s > 1 || screen_coord.t < 0 || screen_coord.t > 1) {dist = 9999; break;}
                if (flag == 1 && reflect_dist > dist) {
                    l = 0;
                    h = t_step;
                    for (int j = 0; j < SSR_DIV_MAX_ITER; j++) {
                        t_step = 0.5 * (l + h);
                        reflect_coord = view_coord + (t + t_step) * direction;
                        reflect_dist = length(reflect_coord);
                        screen_coord = view_coord_to_screen_coord(reflect_coord);
                        dist = texture2D(gdepth, screen_coord.st).x;
                        if (reflect_dist > dist)  h = t_step;
                        else l = t_step;
                    }
                    if (reflect_dist > dist - 1e-2 && reflect_dist < dist + 1e-2 && abs(dist - texture2D(gdepth, nearest(screen_coord.st)).x) < 1) {
                        vec4 color_data = texture2D(gcolor, screen_coord.st);
                        vec3 color = color_data.rgb;
                        float alpha = color_data.a;
                        reflect_color = color;
                        t_oc = 0;
                        hit = 1;
                        break;
                    }
                    else {
                        flag = 0;
                        dist_in = reflect_dist;
                        t_in = t + t_step;
                        k_in = k;
                    }
                }
                else if (flag == 0 && reflect_dist < dist) {
                    flag = 1;
                    t_oc += (t - t_in);
                }
                t += t_step;
            }
            if (flag == 0)
                t_oc += (t - t_in);
            if (hit == 0) {
                vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
                vec3 ray_dir = normalize(view_coord_to_world_coord(direction * 100));
                if (isEyeInWater == 0) {
                    float k = fog(dist0, FOG_AIR_DECAY);
                    reflect_color = k * SKY_ILLUMINATION_INTENSITY * lumi_data.w * LUT_sky(ray_dir);
                    color += k * SKY_ILLUMINATION_INTENSITY * lumi_data.w * cal_sun_bloom(ray_dir, sun_dir);
                }
                else {
                    vec3 sun_light = LUT_sun_color(sun_dir);
                    vec3 moon_light = vec3(0.005);
                    float sunmoon_light_mix = smoothstep(-0.05, 0.05, sun_dir.y);
                    vec3 sunmoon_light = SKY_ILLUMINATION_INTENSITY * mix(moon_light, sun_light, sunmoon_light_mix);
                    vec3 sunmoon_lum = sunmoon_light;
                    reflect_color = fog(dist0, FOG_WATER_DECAY) * sunmoon_lum * cal_water_color(lumi_data.w, 0, 32, fog(abs(32 / ray_dir.y), FOG_WATER_DECAY));
                }
            }
            color = (1 - f_r) * color + f_r * reflect_color;
        }
    }

    gl_FragData[0] = vec4(color, 1.0);
    gl_FragData[1] = vec4(bloom, 1.0);
}