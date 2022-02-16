#version 120

#define PI 3.1415926535898

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

#define SSAO_ENABLE 1 // [0 1]
#define SSAO_SAMPLE_NUM 32   //[4 8 16 32 64 128 256]
#define SSAO_SAMPLE_RADIUS 0.25   //[0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5]
#define SSAO_INTENSITY 1.0   //[0.2 0.4 0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0]
#define SSAO_EPSILON 1e-4

const int RGBA16F = 0;
const int RGBA32F = 0;
const int RGB16F = 0;
const int gcolorFormat = RGBA16F;
const int gnormalFormat = RGBA16F;
const int gdepthFormat = RGBA32F;
const int compositeFormat = RGBA16F;
const int gaux1Format = RGBA16F;
const int gaux2Format = RGBA16F;
const int gaux3Format = RGBA16F;
const int gaux4Format = RGBA16F;
const int shadowMapResolution = 4096;   //[1024 2048 4096] 
const float	sunPathRotation	= -30.0;

uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux3;
uniform sampler2D gaux4;

uniform float frameTimeCounter;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

varying vec2 texcoord;

//----------------------------------------
float state;

void seed(vec2 screenCoord)
{
	state = screenCoord.x * 12.9898 + screenCoord.y * 78.223;
    state *= (1 + fract(sin(state + frameTimeCounter) * 43758.5453));
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

vec3 view_coord_to_screen_coord(vec3 view_coord) {
    vec4 clid_coord = gbufferProjection * vec4(view_coord, 1);
    vec3 ndc_coord = clid_coord.xyz / clid_coord.w;
    vec3 screen_coord = ndc_coord * 0.5 + 0.5;
    return screen_coord;
}

/* DRAWBUFFERS: 01345 */
void main() {
    vec3 color = texture2D(gcolor, texcoord).rgb;
    vec3 translucent = texture2D(composite, texcoord).rgb;
    float depth0 = texture2D(depthtex0, texcoord).x;
    float depth1 = texture2D(depthtex1, texcoord).x;
    vec4 normal_data0 = texture2D(gnormal, texcoord);
    vec3 normal0 = normal_data0.xyz;
    float block_id0 = normal_data0.w;
    vec4 normal_data1 = texture2D(gaux1, texcoord);
    vec4 lumi_data = texture2D(gaux2, texcoord);
    float alpha = 1 - texture2D(gaux3, texcoord).x;
    vec4 translucent_data = texture2D(gaux4, texcoord);
    float block_id1 = translucent_data.x;
    normal_data1.w = block_id1;
    if (block_id1 > 0.5)  lumi_data.w = translucent_data.y;
    else lumi_data.w = lumi_data.y;

    float dist0 = 9999;
    float dist1 = 9999;
    vec3 view_coord;
    
    if (block_id0 > 0.5 || block_id1 > 0.5) {
        vec3 screen_coord = vec3(texcoord, depth0);
        vec3 view_coord_ = screen_coord_to_view_coord(screen_coord);
        dist0 = length(view_coord_);
    }
    if (block_id0 > 0.5) {
        vec3 screen_coord = vec3(texcoord, depth1);
        view_coord = screen_coord_to_view_coord(screen_coord);
        dist1 = length(view_coord);
    }
    
    /* INVERSE GAMMA */
    color = pow(color, vec3(GAMMA));
    translucent = pow(translucent, vec3(GAMMA));

#if SSAO_ENABLE
    /* SSAO */
    if (block_id0 > 0.5) {
        seed(texcoord);
        float ao = 1, ssao_sample_depth;
        vec3 ssao_sample, tangent, bitangent;
        int oc = 0, sum = 0;
        for (int i = 0; i < SSAO_SAMPLE_NUM; i++) {
            ssao_sample = vec3(rand() * 2 - 1, rand(), rand() * 2 - 1);
            if (length(ssao_sample) < 1) {
                tangent = normalize(cross(normal0, normal0.y < 0.707 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
                bitangent = cross(normal0, tangent);
                ssao_sample = SSAO_SAMPLE_RADIUS * (ssao_sample.x * bitangent + ssao_sample.y * normal0 + ssao_sample.z * tangent);
                ssao_sample += view_coord;
                ssao_sample = view_coord_to_screen_coord(ssao_sample);
                sum++;
                ssao_sample_depth = texture2D(depthtex1, ssao_sample.st).x;
                if (ssao_sample.z - SSAO_EPSILON > ssao_sample_depth && ssao_sample.z - 0.001 < ssao_sample_depth) oc++;
            }
        }
        if (sum > 0) ao = 1 - SSAO_INTENSITY * oc / sum;
        lumi_data.z = clamp(ao, 0, 1);
    }
#endif
    
    gl_FragData[0] = vec4(color, alpha);
    gl_FragData[1] = vec4(dist0, dist1, 0.0, 0.0);
    gl_FragData[2] = vec4(translucent, 1.0);
    gl_FragData[3] = normal_data1;
    gl_FragData[4] = lumi_data;
}