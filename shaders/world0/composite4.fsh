#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SKY_ILLUMINATION_INTENSITY 3.0  //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]

#define SSR_STEP_MAX_ITER 100
#define SSR_DIV_MAX_ITER 8
#define SSR_F0 0.04
#define SSR_ETA 1.05

#define AIR_DECAY 0.001     //[0.0001 0.0002 0.0005 0.001 0.002 0.005 0.01 0.02 0.05]
#define FOG_THICKNESS 256

#define WATER_DECAY 0.1     //[0.01 0.02 0.05 0.1 0.2 0.5 1.0]
#define WATER_COLOR pow(vec3(0.0000, 0.1356, 0.2405), vec3(GAMMA))

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
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform int isEyeInWater;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform float sunAngle;
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
    dist -= 1;
    dist = dist < 0 ? 0 : dist;
    dist = dist * decay / 16 + 1;
    dist = dist * dist;
    dist = dist * dist;
    dist = dist * dist;
    dist = dist * dist;
    return 1 / dist;
}

/* DRAWBUFFERS: 03 */
void main() {
    vec4 color_data = texture2D(gcolor, texcoord);
    vec3 color = color_data.rgb;
    float alpha = color_data.a;
    vec3 translucent = texture2D(composite, texcoord).rgb;
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

    vec3 bloom_color = color * alpha;

    float sun_angle = sunAngle < 0.5 ? 0.5 - 2 * abs(sunAngle - 0.25) : 0;
    float sky_light_mix = smoothstep(0, 0.02, sun_angle);
    float sky_brightness = SKY_ILLUMINATION_INTENSITY * mix(0.005, 1, sky_light_mix);

    /* FOG */
    vec3 fog_color = pow(fogColor, vec3(GAMMA));
    fog_color *= clamp(sky_brightness / 2, 1, 100);
    if (block_id1 < 1.5 && block_id0 > 0.5) color = mix(fog_color, color, fog(dist1, AIR_DECAY));
    if (block_id1 < 0.5 && block_id0 < 0.5) color = mix(fog_color, color, fog(FOG_THICKNESS, AIR_DECAY));

    int is_water_out = (isEyeInWater == 0 && block_id1 > 1.5) ? 1 : 0;
    int is_water_in = (isEyeInWater == 1) ? 1 : 0;
    if (block_id1 > 0.5 || is_water_in == 1) {
        vec3 sky_color = mix(fog_color, pow(skyColor, vec3(GAMMA)) * lumi_data.w, fog(FOG_THICKNESS, AIR_DECAY));
        vec3 water_color = WATER_COLOR * sky_brightness * lumi_data.w;
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
            vec3 old_normal = normal;
            normal += 3 * offset;
            normal = normalize(normal);
            direction = reflect(normalize(view_coord), normal);
            if (dot(direction, old_normal) < 0) direction = normalize(direction - 2 * dot(direction, old_normal) * old_normal);
            water_depth = dist1 - dist0;
            water_depth = water_depth < 0 ? 0 : water_depth;
            float sin_ = length(cross(direction, normal));
            vec2 tex_coord = texcoord - 0.5 * water_depth * sin_ / dist1 * offset.xy;
            if (texture2D(gaux1, tex_coord).w > 1.5) {
                color_data = texture2D(gcolor, tex_coord);
                color = color_data.rgb;
                alpha = color_data.a;
                bloom_color = color * alpha;
                translucent = texture2D(composite, tex_coord).rgb;
                dist_data = texture2D(gdepth, tex_coord);
                dist1 = dist_data.y;
                water_depth = dist1 - dist0;
                water_depth = water_depth < 0 ? 0 : water_depth;
            }
        }
        else {
            direction = reflect(normalize(view_coord), normal);
        }

        if (is_water_out == 1) {
            color = mix(water_color, color, fog(water_depth, WATER_DECAY));
            color = mix(fog_color, color, fog(dist0, AIR_DECAY));   // FOG
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
            int i, flag = 1;
            f_r = SSR_F0 + (1 - SSR_F0) * f_r * f_r * f_r * f_r * f_r;
            for (i = 0; i < SSR_STEP_MAX_ITER; i++) {
                k = length((direction - dot(direction, reflect_coord) / dot(reflect_coord, reflect_coord) * reflect_coord).xy);
                if (is_water_in == 1 && reflect_dist > 50) i = SSR_STEP_MAX_ITER - 1;
                if (i == SSR_STEP_MAX_ITER - 1)
                    t_step = far;
                else {
                    t_step = 0.001 * -view_coord.z / k * (reflect_dist + 10);
                    t_step = t_step > 2 ? 2 : t_step;
                    t_step *= 0.75 + 0.5 * rand();
                }
                reflect_coord = view_coord + (t + t_step) * direction;
                if (reflect_coord.z > 0) {
                    t_oc = 0;
                    flag = 1;
                    break;
                }
                reflect_dist = length(reflect_coord);
                screen_coord = view_coord_to_screen_coord(reflect_coord);
                dist = texture2D(gdepth, screen_coord.st).y;
                if (screen_coord.s < 0 || screen_coord.s > 1 || screen_coord.t < 0 || screen_coord.t > 1) {dist = 9999; break;}
                if (i == SSR_STEP_MAX_ITER - 1) {i++; break;}
                if (flag == 1 && reflect_dist > dist) {
                    l = 0;
                    h = t_step;
                    for (int j = 0; j < SSR_DIV_MAX_ITER; j++) {
                        t_step = 0.5 * (l + h);
                        reflect_coord = view_coord + (t + t_step) * direction;
                        reflect_dist = length(reflect_coord);
                        screen_coord = view_coord_to_screen_coord(reflect_coord);
                        dist = texture2D(gdepth, screen_coord.st).y;
                        if (reflect_dist > dist)  h = t_step;
                        else l = t_step;
                    }
                    if (reflect_dist > dist - 1e-2 && reflect_dist < dist + 1e-2 && abs(dist - texture2D(gdepth, nearest(screen_coord.st)).y) < 1) {
                        reflect_color = texture2D(gcolor, screen_coord.st).rgb;
                        t_oc = 0;
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
            else if (i == SSR_STEP_MAX_ITER) {
                dist = texture2D(gdepth, screen_coord.st).x;
                reflect_color = texture2D(gcolor, screen_coord.st).rgb;
                i = 0;
            }
            if (isEyeInWater == 0) {    // FOG
                if (texture2D(gnormal, screen_coord.st).w > 0.5)
                    reflect_color = mix(fog_color, reflect_color, fog(dist, AIR_DECAY));
                else
                    reflect_color = mix(fog_color, reflect_color, fog(FOG_THICKNESS, AIR_DECAY));
            }
            else
                reflect_color = mix(water_color, reflect_color, fog(length(reflect_coord - view_coord), WATER_DECAY));
            reflect_color = mix(t_oc > 5 ? mix(fog_color, vec3(0.0), fog(dist_in, AIR_DECAY)) : isEyeInWater == 0 ? sky_color : water_color, reflect_color,
                smoothstep(0, 0.01, 1 - (float(i) / SSR_STEP_MAX_ITER)) *
                smoothstep(0, 0.01, screen_coord.s) *
                smoothstep(0, 0.01, 1 - screen_coord.s) *
                smoothstep(0, 0.01, screen_coord.t) *
                smoothstep(0, 0.01, 1 - screen_coord.t));
            /* TRANSLUCENT */
            translucent = pow(translucent, vec3(GAMMA));
            translucent = mix(fog_color * (1 - alpha), translucent, fog(dist0, AIR_DECAY));   // FOG
            color = color * alpha + translucent;
            color = (1 - f_r) * color + f_r * reflect_color;
        }

        if (is_water_in == 1) {
            water_depth = dist0;
            water_depth = water_depth < 0 ? 0 : water_depth;
            lumi_data.w = eyeBrightnessSmooth.y / 480. + 0.5;
            water_color = WATER_COLOR * sky_brightness * lumi_data.w;
            color = mix(water_color, color, fog(water_depth, WATER_DECAY));
        }
    }

    /* BLOOM EXTRACT */
    bloom_color = pow(bloom_color, vec3(1 / GAMMA));
    if (block_id0 > 1.5) {
        bloom_color = mix(vec3(0.0), bloom_color, smoothstep(0.4, 0.6, grayscale(bloom_color)));
    }
    else {
        bloom_color = 0.5 * mix(vec3(0.0), bloom_color, smoothstep(1.5, 2, grayscale(bloom_color)));
    }

    gl_FragData[0] = vec4(color, 1.0);
    gl_FragData[1] = vec4(bloom_color, 1.0); 
}