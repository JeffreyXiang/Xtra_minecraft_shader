#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SSAO_ENABLE 1 // [0 1]
#define SSAO_DISTANCE 64
#define SSAO_RES_SCALE 0.5   //[0.25 0.5 1]
#define SSAO_SAMPLE_NUM 32   //[4 8 16 32 64 128 256]
#define SSAO_SAMPLE_RADIUS 0.5   //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SSAO_INTENSITY 1.0   //[0.2 0.4 0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0]

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D depthtex1;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D colortex15;

uniform float frameTimeCounter;

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

vec3 view_coord_to_screen_coord(vec3 view_coord) {
    vec4 clid_coord = gbufferProjection * vec4(view_coord, 1);
    vec3 ndc_coord = clid_coord.xyz / clid_coord.w;
    vec3 screen_coord = ndc_coord * 0.5 + 0.5;
    return screen_coord;
}

/* RENDERTARGETS: 0,1,3,6,7,15 */
void main() {
    vec3 color_s = texture2D(gcolor, texcoord).rgb;
    vec3 data_w = texture2D(gdepth, texcoord).rgb;
    float depth_w = data_w.x;
    float sky_light_w = data_w.y;
    float block_id_w = data_w.z - 1;
    vec4 normal_data_s = texture2D(gnormal, texcoord);
    vec3 normal_s = normal_data_s.rgb;
    float block_id_s = normal_data_s.a;
    float depth_s = texture2D(depthtex1, texcoord).x;
    vec4 color_data_g = texture2D(composite, texcoord);
    vec3 color_g = color_data_g.rgb;
    float alpha = color_data_g.a;
    vec2 lum_data_s = texture2D(gaux3, texcoord).xy;
    float block_light_s = lum_data_s.x;
    float sky_light_s = lum_data_s.y;
    vec3 data_g = texture2D(gaux4, texcoord).xyz;
    float depth_g = data_g.x;
    float sky_light_g = data_g.y;
    float block_id_g = data_g.z;

    float dist_s = 9999;
    float dist_w = 9999;
    float dist_g = 9999;

    if (block_id_s > 0.5) {
        vec3 screen_coord = vec3(texcoord, depth_s);
        vec3 view_coord_ = screen_coord_to_view_coord(screen_coord);
        dist_s = length(view_coord_);
    }
    else depth_s = 2;
    if (block_id_w > 0.5){
        vec3 screen_coord = vec3(texcoord, depth_w);
        vec3 view_coord_ = screen_coord_to_view_coord(screen_coord);
        dist_w = length(view_coord_);
    }
    else depth_w = 2;
    if (block_id_g > 0.5){
        vec3 screen_coord = vec3(texcoord, depth_g);
        vec3 view_coord_ = screen_coord_to_view_coord(screen_coord);
        dist_g = length(view_coord_);
    }
    else depth_g = 2;
    
    
    /* INVERSE GAMMA */
    color_s = pow(color_s, vec3(GAMMA));
    color_g = pow(color_g, vec3(GAMMA));

    float ao = 1;
#if SSAO_ENABLE
    /* SSAO */
    vec2 ssao_texcoord = (texcoord - 0.5) / SSAO_RES_SCALE + 0.5;
    if (ssao_texcoord.x > 0 && ssao_texcoord.x < 1 && ssao_texcoord.y > 0 && ssao_texcoord.y < 1) {
        vec4 ssao_normal_data_s = texture2D(gnormal, ssao_texcoord);
        vec3 ssao_normal_s = ssao_normal_data_s.rgb;
        float ssao_block_id_s = ssao_normal_data_s.a;
        if (ssao_block_id_s > 0.5) {
            vec3 ssao_screen_coord = vec3(ssao_texcoord, texture2D(depthtex1, ssao_texcoord).x);
            vec3 ssao_view_coord = screen_coord_to_view_coord(ssao_screen_coord);
            float ssao_dist_s = length(ssao_view_coord);
            if (ssao_dist_s < SSAO_DISTANCE) {
                seed(ssao_texcoord);
                float ssao_sample_depth, y, xz, theta, r;
                vec3 ssao_sample, tangent, bitangent;
                int oc = 0, sum = 0;
                for (int i = 0; i < SSAO_SAMPLE_NUM; i++) {
                    y = rand();
                    xz = sqrt(1 - y * y);
                    theta = 2 * PI * rand();
                    r = rand();
                    r = r * SSAO_SAMPLE_RADIUS;
                    ssao_sample = r * vec3(xz * cos(theta), y, xz * sin(theta));
                    tangent = normalize(cross(ssao_normal_s, ssao_normal_s.y < 0.707 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
                    bitangent = cross(ssao_normal_s, tangent);
                    ssao_sample = SSAO_SAMPLE_RADIUS * (ssao_sample.x * bitangent + ssao_sample.y * ssao_normal_s + ssao_sample.z * tangent);
                    ssao_sample += ssao_view_coord;
                    ssao_sample = view_coord_to_screen_coord(ssao_sample);
                    sum++;
                    ssao_sample_depth = texture2D(depthtex1, ssao_sample.st).x;
                    if (ssao_sample.z > ssao_sample_depth && (ssao_sample.z - ssao_sample_depth) * ssao_dist_s < 0.02 * SSAO_SAMPLE_RADIUS) oc++;
                }
                if (sum > 0) ao = 1 - SSAO_INTENSITY * oc / sum * (1 - smoothstep(SSAO_DISTANCE - 32, SSAO_DISTANCE, ssao_dist_s));
                ao = clamp(ao, 0, 1);
            }
        }
    }
#endif

    /* LUTS */
    vec4 LUT_data = vec4(0.0);
    vec2 LUT_texcoord = vec2(texcoord.x / 256 * viewWidth, texcoord.y / 256 * viewHeight);
    if (LUT_texcoord.x < 1 && LUT_texcoord.y < 1)
        LUT_data = texture2D(colortex15, LUT_texcoord);
    
    gl_FragData[0] = vec4(color_s, ao);
    gl_FragData[1] = vec4(depth_s, depth_w, depth_g, 0.0);
    gl_FragData[2] = vec4(color_g, alpha);
    gl_FragData[3] = vec4(block_light_s, sky_light_s, sky_light_w, sky_light_g);
    gl_FragData[4] = vec4(dist_s, dist_w, dist_g, 0.0);
    gl_FragData[5] = LUT_data;
;
}