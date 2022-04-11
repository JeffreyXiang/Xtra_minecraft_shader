#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SKY_ILLUMINATION_INTENSITY 3.0  //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]

#define SSR_STEP_MAX_ITER 36
#define SSR_DIV_MAX_ITER 6
#define SSR_F0 0.04
#define SSR_ETA 1.05

#define FOG_AIR_DECAY 0.001     //[0.0001 0.0002 0.0005 0.001 0.002 0.005 0.01 0.02 0.05]
#define FOG_AIR_THICKNESS 256
#define FOG_WATER_DECAY 0.1     //[0.01 0.02 0.05 0.1 0.2 0.5 1.0]
#define FOG_WATER_THICKNESS 32

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D colortex15;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D noisetex;

uniform float far;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform float sunAngle;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform float frameTimeCounter;
uniform ivec2 eyeBrightnessSmooth;
uniform int isEyeInWater;
uniform vec3 cameraPosition;

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

//----------------------------------------
float state;

void seed(vec2 screenCoord)
{
	state = screenCoord.x * 12.9898 + screenCoord.y * 78.223;
    // state *= (1 + fract(sin(state + frameTimeCounter) * 43758.5453));
}

float rand(){
    float val = fract(sin(state) * 43758.5453);
    state = fract(state) * 38.287;
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

/* DRAWBUFFERS: 0 */
void main() {
    vec3 color_s;
    float block_id_s, sky_light_s;
    vec3 reflect_color_w = vec3(0.0);
    vec4 color_data_g;
    vec3 color_g, reflect_color_g;
    float alpha, reflect_sky_light_g, reflect_sky_light_w;
    vec3 depth_data = texture2D(gdepth, texcoord).xyz;
    float depth_s = depth_data.x;
    float depth_w = depth_data.y;
    float depth_g = depth_data.z;
    vec2 lum_data = texture2D(gaux3, texcoord).zw;
    float sky_light_w = lum_data.x;
    float sky_light_g = lum_data.y;
    vec3 dist_data = texture2D(gaux4, texcoord).xyz;
    float dist_s = dist_data.x;
    float dist_w = dist_data.y;
    float dist_g = dist_data.z;

    vec3 view_coord_w, view_coord_g, normal_w, normal_g;
    if (depth_w < 1.5) {
        normal_w = texture2D(gaux1, texcoord).rgb;
        vec3 screen_coord = vec3(texcoord, depth_w);
        view_coord_w = screen_coord_to_view_coord(screen_coord);
    }

    /* WATER REFRACTION */
    vec2 texcoord_s = texcoord, texcoord_g = texcoord;
    vec3 old_normal_w;
    if (depth_w < 1.5 && !(isEyeInWater == 1 && depth_g < depth_w)) {
        vec3 world_coord_w = view_coord_to_world_coord(view_coord_w) + cameraPosition;
        vec2 d0 = vec2(0.4472, 0.8944);
        vec2 d1 = vec2(0.8944, 0.4472);
        vec2 d0T = vec2(-d0.y, d0.x);
        vec2 d1T = vec2(-d1.y, d1.x);
        vec3 offset = vec3(
            d0T * wave(dot(d0, world_coord_w.xz)) + d1T * wave(dot(d1, world_coord_w.xz)),
        0);
        vec2 nd0 = vec2(-0.0806,  0.1613);
        vec2 nd1 = vec2(-0.0602, -0.1844);
        vec2 nd2 = vec2( 0.1758,  0.1074);
        vec2 nd3 = vec2(-0.0480, -0.0813);
        vec2 nd4 = vec2( 0.2454,  0.2085);
        vec2 nd5 = vec2( 0.0343, -0.3817);
        offset += 0.02 * (
            texture2D(noisetex, fract((world_coord_w.xz + frameTimeCounter * 3 * nd0) / 128)).rgb +
            texture2D(noisetex, fract((world_coord_w.xz + frameTimeCounter * 3 * nd1) / 128)).rgb +
            texture2D(noisetex, fract((world_coord_w.xz + frameTimeCounter * 3 * nd2) / 128)).rgb +
            texture2D(noisetex, fract((world_coord_w.xz + frameTimeCounter * 3 * nd3) / 128)).rgb +
            texture2D(noisetex, fract((world_coord_w.xz + frameTimeCounter * 3 * nd4) / 128)).rgb +
            texture2D(noisetex, fract((world_coord_w.xz + frameTimeCounter * 3 * nd5) / 128)).rgb - 3);
        old_normal_w = normal_w;
        normal_w += 2 * offset;
        normal_w = normalize(normal_w);
        float water_depth = dist_s - dist_w;
        water_depth = water_depth < 0 ? 0 : water_depth;
        vec2 texcoord_ = texcoord - 0.1 * water_depth / dist_s * offset.xy;
        if (texture2D(gdepth, texcoord_).y < 1.5) {
            texcoord_s = texcoord_;
        }
        dist_g = (depth_g < 1.5 ? dist_g : dist_s);
        water_depth = dist_g - dist_w;
        if (water_depth > 0) {
            texcoord_ = texcoord - 0.1 * water_depth / dist_g * offset.xy;
            vec2 depth_data = texture2D(gdepth, texcoord_).yz;
            if (depth_data.x < depth_data.y) {
                texcoord_g = texcoord_;
            }
        }
    }

    /* WATER REFLECTION */
    float fr_w = 0, reflect_dist_w = 0;
    int hit_w = 0;
    vec2 reflect_texcoord_w = vec2(0.0);
    vec3 reflect_direction_w;
    if (depth_w < 1.5 && !(isEyeInWater == 1 && depth_g < depth_w)) {
        seed(texcoord);
        reflect_direction_w = reflect(normalize(view_coord_w), normal_w);
        if (dot(reflect_direction_w, old_normal_w) < 0) reflect_direction_w = normalize(reflect_direction_w - 2 * dot(reflect_direction_w, old_normal_w) * old_normal_w);
        if (isEyeInWater == 0) fr_w = 1 - dot(reflect_direction_w, normal_w);
        else {
            float sin_t = SSR_ETA * length(cross(reflect_direction_w, normal_w));
            sin_t = sin_t > 1 ? 1 : sin_t;
            fr_w = 1 - sqrt(1 - sin_t * sin_t);
        }
        fr_w = SSR_F0 + (1 - SSR_F0) * fr_w * fr_w * fr_w * fr_w * fr_w;
        float t = 0, t_oc = 0, t_step, t_in, k, l, h, dist, reflect_dist = dist_w;
        vec3 reflect_coord = view_coord_w, screen_coord;
        int i, visible = 1;
        for (i = 0; i < SSR_STEP_MAX_ITER; i++) {
            k = length(reflect_direction_w - dot(reflect_direction_w, reflect_coord) / dot(reflect_coord, reflect_coord) * reflect_coord);
            k = k / reflect_dist;
            k = k > 0.2 ? 0.2 : k;
            t_step = 0.02 / k;
            t_step = t_step > 10 ? 10 : t_step;
            t_step *= 0.75 + 0.5 * rand();
            reflect_coord = view_coord_w + (t + t_step) * reflect_direction_w;
            if (reflect_coord.z > 0) {
                t_oc = 0;
                visible = 1;
                break;
            }
            reflect_dist = length(reflect_coord);
            screen_coord = view_coord_to_screen_coord(reflect_coord);
            if (screen_coord.s < 0 || screen_coord.s > 1 || screen_coord.t < 0 || screen_coord.t > 1) {break;}
            dist = texture2D(gaux4, screen_coord.st).x;
            if (visible == 1 && reflect_dist > dist) {
                l = 0;
                h = t_step;
                for (int j = 0; j < SSR_DIV_MAX_ITER; j++) {
                    t_step = 0.5 * (l + h);
                    reflect_coord = view_coord_w + (t + t_step) * reflect_direction_w;
                    reflect_dist = length(reflect_coord);
                    screen_coord = view_coord_to_screen_coord(reflect_coord);
                    dist = texture2D(gaux4, screen_coord.st).x;
                    if (reflect_dist > dist)  h = t_step;
                    else l = t_step;
                }
                if (reflect_dist > dist - 1e-3 / k && reflect_dist < dist + 1e-3 / k && abs(dist - texture2D(gaux4, nearest(screen_coord.st)).x) < 10) {
                    hit_w = 1;
                    reflect_texcoord_w = screen_coord.st;
                    reflect_dist_w = reflect_dist;
                    break;
                }
                else {
                    visible = 0;
                    t_in = t + t_step;
                }
            }
            else if (visible == 0 && reflect_dist < dist) {
                visible = 1;
                t_oc += (t - t_in);
            }
            t += t_step;
        }
        if (visible == 0)
            t_oc += (t - t_in);
    }

    depth_g = texture2D(gdepth, texcoord_g).z;
    if (depth_g < 1.5) {
        dist_g = texture2D(gaux4, texcoord_g).z;
        normal_g = texture2D(gaux2, texcoord_g).rgb;
        vec3 screen_coord = vec3(texcoord_g, depth_g);
        view_coord_g = screen_coord_to_view_coord(screen_coord);
    }

    /* GLASS REFLECTION */
    float fr_g = 0, reflect_dist_g = 0;
    int hit_g = 0;
    vec2 reflect_texcoord_g = vec2(0.0);
    vec3 reflect_direction_g;
    if (depth_g < 1.5 && depth_w > depth_g) {
        seed(texcoord);
        reflect_direction_g = reflect(normalize(view_coord_g), normal_g);
        if (isEyeInWater == 0) fr_g = 1 - dot(reflect_direction_g, normal_g);
        else {
            float sin_t = SSR_ETA * length(cross(reflect_direction_g, normal_g));
            sin_t = sin_t > 1 ? 1 : sin_t;
            fr_g = 1 - sqrt(1 - sin_t * sin_t);
        }
        fr_g = SSR_F0 + (1 - SSR_F0) * fr_g * fr_g * fr_g * fr_g * fr_g;
        float t = 0, t_oc = 0, t_step, t_in, k, l, h, dist, reflect_dist = dist_g;
        vec3 reflect_coord = view_coord_g, screen_coord;
        int i, visible = 1;
        for (i = 0; i < SSR_STEP_MAX_ITER; i++) {
            k = length(reflect_direction_g - dot(reflect_direction_g, reflect_coord) / dot(reflect_coord, reflect_coord) * reflect_coord);
            k = k / reflect_dist;
            k = k > 0.2 ? 0.2 : k;
            t_step = 0.02 / k;
            t_step = t_step > 10 ? 10 : t_step;
            t_step *= 0.75 + 0.5 * rand();
            reflect_coord = view_coord_g + (t + t_step) * reflect_direction_g;
            if (reflect_coord.z > 0) {
                t_oc = 0;
                visible = 1;
                break;
            }
            reflect_dist = length(reflect_coord);
            screen_coord = view_coord_to_screen_coord(reflect_coord);
            if (screen_coord.s < 0 || screen_coord.s > 1 || screen_coord.t < 0 || screen_coord.t > 1) {break;}
            dist = texture2D(gaux4, screen_coord.st).x;
            if (visible == 1 && reflect_dist > dist) {
                l = 0;
                h = t_step;
                for (int j = 0; j < SSR_DIV_MAX_ITER; j++) {
                    t_step = 0.5 * (l + h);
                    reflect_coord = view_coord_g + (t + t_step) * reflect_direction_g;
                    reflect_dist = length(reflect_coord);
                    screen_coord = view_coord_to_screen_coord(reflect_coord);
                    dist = texture2D(gaux4, screen_coord.st).x;
                    if (reflect_dist > dist)  h = t_step;
                    else l = t_step;
                }
                if (reflect_dist > dist - 1e-3 / k && reflect_dist < dist + 1e-3 / k && abs(dist - texture2D(gaux4, nearest(screen_coord.st)).x) < 10) {
                    hit_g = 1;
                    reflect_texcoord_g = screen_coord.st;
                    reflect_dist_g = reflect_dist;
                    break;
                }
                else {
                    visible = 0;
                    t_in = t + t_step;
                }
            }
            else if (visible == 0 && reflect_dist < dist) {
                visible = 1;
                t_oc += (t - t_in);
            }
            t += t_step;
        }
        if (visible == 0)
            t_oc += (t - t_in);
    }

    /* LIGHT PROPAGATION */
    float k;
    float eye_brightness = eyeBrightnessSmooth.y / 240.;
    vec3 fog_color = eye_brightness * fogColor;
    color_s = texture2D(gcolor, texcoord_s).rgb;
    depth_s = texture2D(gdepth, texcoord_s).x;
    block_id_s = texture2D(gnormal, texcoord_s).w;
    sky_light_s = texture2D(gaux3, texcoord_s).y;
    dist_s = block_id_s > 0.5 ? texture2D(gaux4, texcoord_s).x : FOG_AIR_THICKNESS;
    if (isEyeInWater == 0) {
        if (depth_w < 1.5 && !(isEyeInWater == 1 && depth_g < depth_w)) {
            vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
            vec3 sun_light = LUT_sun_color(sun_dir);
            vec3 moon_light = vec3(0.005);
            float sunmoon_light_mix = smoothstep(-0.05, 0.05, sun_dir.y);
            vec3 sunmoon_light = SKY_ILLUMINATION_INTENSITY * mix(moon_light, sun_light, sunmoon_light_mix);
            k = fog(dist_s - dist_w, FOG_WATER_DECAY);
            float y_s = view_coord_to_world_coord(screen_coord_to_view_coord(vec3(texcoord_s, depth_s))).y;
            float y_w = view_coord_to_world_coord(view_coord_w).y;
            color_s = k * color_s + sunmoon_light * sky_light_w * cal_water_color(sky_light_w, sky_light_s, y_w - y_s, k);
            color_s = mix(fog_color, color_s, fog(dist_w, FOG_AIR_DECAY));
            if (hit_w == 1) {
                reflect_color_w = texture2D(gcolor, reflect_texcoord_w).rgb;
                reflect_color_w = mix(fog_color, reflect_color_w, fog(reflect_dist_w, FOG_AIR_DECAY));
            }
            else {
                vec3 ray_dir = normalize(view_coord_to_world_coord(reflect_direction_w * 100));
                reflect_color_w = SKY_ILLUMINATION_INTENSITY * sky_light_w * LUT_sky(ray_dir);
                reflect_color_w += SKY_ILLUMINATION_INTENSITY / fr_w * sky_light_w * cal_sun_bloom(ray_dir, sun_dir);
                reflect_color_w = mix(fog_color, reflect_color_w, fog(FOG_AIR_THICKNESS, FOG_AIR_DECAY));
            }
            if (depth_g < 1.5) {
                color_data_g = texture2D(composite, texcoord_g);
                color_g = color_data_g.rgb;
                alpha = color_data_g.a;
                alpha = (1 - fr_g) * alpha + fr_g;
                if (depth_w > depth_g) {
                    if (hit_g == 1) {
                    reflect_color_g = texture2D(gcolor, reflect_texcoord_g).rgb;
                    reflect_color_g = mix(fog_color, reflect_color_g, fog(reflect_dist_g, FOG_AIR_DECAY));
                    }
                    else {
                        vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
                        vec3 ray_dir = normalize(view_coord_to_world_coord(reflect_direction_g * 100));
                        reflect_color_g = SKY_ILLUMINATION_INTENSITY * sky_light_g * LUT_sky(ray_dir);
                        reflect_color_g += SKY_ILLUMINATION_INTENSITY / fr_g * sky_light_g * cal_sun_bloom(ray_dir, sun_dir);
                        reflect_color_g = mix(fog_color, reflect_color_g, fog(FOG_AIR_THICKNESS, FOG_AIR_DECAY));
                    }
                    color_g = (1 - fr_g) * color_g + fr_g * reflect_color_g; 
                    color_g = mix(alpha * fog_color, color_g, fog(dist_g, FOG_AIR_DECAY));
                }
                else {
                    k = fog(dist_g - dist_w, FOG_WATER_DECAY);
                    color_g = k * color_g + alpha * sunmoon_light * sky_light_w * cal_water_color(sky_light_w, sky_light_s, y_w - y_s, k);
                }
            }
        }
        else {
            color_s = mix(fog_color, color_s, fog(dist_s, FOG_AIR_DECAY));
            if (depth_g < 1.5) {
                color_data_g = texture2D(composite, texcoord_g);
                color_g = color_data_g.rgb;
                alpha = color_data_g.a;
                alpha = (1 - fr_g) * alpha + fr_g;
                if (hit_g == 1) {
                    reflect_color_g = texture2D(gcolor, reflect_texcoord_g).rgb;
                    reflect_color_g = mix(fog_color, reflect_color_g, fog(reflect_dist_g, FOG_AIR_DECAY));
                }
                else {
                    vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
                    vec3 ray_dir = normalize(view_coord_to_world_coord(reflect_direction_g * 100));
                    reflect_color_g = SKY_ILLUMINATION_INTENSITY * sky_light_g * LUT_sky(ray_dir);
                    reflect_color_g += SKY_ILLUMINATION_INTENSITY / fr_g * sky_light_g * cal_sun_bloom(ray_dir, sun_dir);
                    reflect_color_g = mix(fog_color, reflect_color_g, fog(FOG_AIR_THICKNESS, FOG_AIR_DECAY));
                }
                color_g = (1 - fr_g) * color_g + fr_g * reflect_color_g; 
                color_g = mix(alpha * fog_color, color_g, fog(dist_g, FOG_AIR_DECAY));
            }
        }
    }
    else if (isEyeInWater == 1) {
        vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
        vec3 sun_light = LUT_sun_color(sun_dir);
        vec3 moon_light = vec3(0.005);
        float sunmoon_light_mix = smoothstep(-0.05, 0.05, sun_dir.y);
        vec3 sunmoon_light = SKY_ILLUMINATION_INTENSITY * mix(moon_light, sun_light, sunmoon_light_mix);
        if (depth_w < 1.5 && !(isEyeInWater == 1 && depth_g < depth_w)) {
            color_s = mix(fog_color, color_s, fog(dist_s - dist_w, FOG_AIR_DECAY));
            k = fog(dist_w, FOG_WATER_DECAY);
            float y_w = view_coord_to_world_coord(view_coord_w).y;
            color_s = k * color_s + sunmoon_light * cal_water_color(eye_brightness, sky_light_w, y_w, k);
            // if (hit_w == 1) {
            //     reflect_color_w = texture2D(gcolor, reflect_texcoord_w).rgb;
            //     reflect_color_w = mix(fog_color, reflect_color_w, fog(reflect_dist_w, FOG_AIR_DECAY));
            // }
            // else {
            //     vec3 ray_dir = normalize(view_coord_to_world_coord(reflect_direction_w * 100));
            //     reflect_color_w = SKY_ILLUMINATION_INTENSITY * sky_light_w * LUT_sky(ray_dir);
            //     reflect_color_w += SKY_ILLUMINATION_INTENSITY / fr_w * sky_light_w * cal_sun_bloom(ray_dir, sun_dir);
            //     reflect_color_w = mix(fog_color, reflect_color_w, fog(FOG_AIR_THICKNESS, FOG_AIR_DECAY));
            // }
            // if (depth_g < 1.5) {
            //     color_data_g = texture2D(composite, texcoord_g);
            //     color_g = color_data_g.rgb;
            //     alpha = color_data_g.a;
            //     alpha = (1 - fr_g) * alpha + fr_g;
            //     if (depth_w > depth_g) {
            //         if (hit_g == 1) {
            //         reflect_color_g = texture2D(gcolor, reflect_texcoord_g).rgb;
            //         reflect_color_g = mix(fog_color, reflect_color_g, fog(reflect_dist_g, FOG_AIR_DECAY));
            //         }
            //         else {
            //             vec3 sun_dir = normalize(view_coord_to_world_coord(sunPosition));
            //             vec3 ray_dir = normalize(view_coord_to_world_coord(reflect_direction_g * 100));
            //             reflect_color_g = SKY_ILLUMINATION_INTENSITY * sky_light_g * LUT_sky(ray_dir);
            //             reflect_color_g += SKY_ILLUMINATION_INTENSITY / fr_g * sky_light_g * cal_sun_bloom(ray_dir, sun_dir);
            //             reflect_color_g = mix(fog_color, reflect_color_g, fog(FOG_AIR_THICKNESS, FOG_AIR_DECAY));
            //         }
            //         color_g = (1 - fr_g) * color_g + fr_g * reflect_color_g; 
            //         color_g = mix(alpha * fog_color, color_g, fog(dist_g, FOG_AIR_DECAY));
            //     }
            //     else {
            //         k = fog(dist_g - dist_w, FOG_WATER_DECAY);
            //         color_g = k * color_g + alpha * sunmoon_light * sky_light_w * cal_water_color(sky_light_w, sky_light_s, y_w - y_s, k);
            //     }
            // }
        }
        else {
            k = fog(dist_s, FOG_WATER_DECAY);
            float y_s = view_coord_to_world_coord(screen_coord_to_view_coord(vec3(texcoord_s, depth_s))).y;
            color_s = k * color_s + sunmoon_light * cal_water_color(eye_brightness, sky_light_s, y_s, k);
            if (depth_g < 1.5) {
                color_data_g = texture2D(composite, texcoord_g);
                color_g = color_data_g.rgb;
                alpha = color_data_g.a;
                alpha = (1 - fr_g) * alpha + fr_g;
                if (hit_g == 1) {
                    reflect_color_g = texture2D(gcolor, reflect_texcoord_g).rgb;
                    reflect_sky_light_g = texture2D(gaux3, reflect_texcoord_g).w;
                    k = fog(reflect_dist_g, FOG_WATER_DECAY);
                    vec3 ray_dir = normalize(view_coord_to_world_coord(reflect_direction_g * 100));
                    float y_diff = reflect_dist_g * ray_dir.y;
                    reflect_color_g = k * reflect_color_g + sunmoon_light * sky_light_g * cal_water_color(sky_light_g, reflect_sky_light_g, y_diff, k);
                }
                else {
                    vec3 ray_dir = normalize(view_coord_to_world_coord(reflect_direction_g * 100));
                    k = fog(FOG_WATER_THICKNESS / abs(ray_dir.y), FOG_WATER_DECAY);
                    float y_diff = reflect_dist_g * ray_dir.y;
                    reflect_color_g = sunmoon_light * sky_light_g / (1 - k) * cal_water_color(sky_light_g, 1, FOG_WATER_THICKNESS, k);
                }
                color_g = (1 - fr_g) * color_g + fr_g * reflect_color_g; 
                k = fog(dist_g, FOG_WATER_DECAY);
                float y_g = view_coord_to_world_coord(view_coord_g).y;
                color_g = k * color_g + alpha * sunmoon_light * cal_water_color(eye_brightness, sky_light_g, y_g, k);
            }
        }
    }
    if (depth_w > depth_g)
        color_s = (1 - alpha) * (1 - fr_w) * color_s + color_g + (1 - alpha) * fr_w * reflect_color_w;
    else
        color_s = (1 - alpha) * (1 - fr_w) * color_s + (1 - fr_w) * color_g + fr_w * reflect_color_w;
    gl_FragData[0] = vec4(color_s, 1.0);
}