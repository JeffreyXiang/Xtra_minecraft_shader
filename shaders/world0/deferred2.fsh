#version 120

#define PI 3.1415926535898

#define CLOUDS_ENABLE 1 // [0 1]

#define LUT_WIDTH 512
#define LUT_HEIGHT 512

uniform sampler2D colortex15;

varying vec2 texcoord;

/* RENDERTARGETS: 15 */
void main() {
    /* LUT SKY LIGHT */
    vec4 LUT_data = texture2D(colortex15, texcoord);

    if (texcoord.s > 0. / LUT_WIDTH && texcoord.s < 256. / LUT_WIDTH && texcoord.t > 256. / LUT_HEIGHT && texcoord.t < 512. / LUT_HEIGHT)
        #if CLOUDS_ENABLE
            LUT_data.rgb =
                texture2D(colortex15, texcoord + vec2(256. / LUT_WIDTH, -256. / LUT_HEIGHT)).rgb * LUT_data.a +
                LUT_data.rgb +
                texture2D(colortex15, texcoord + vec2(256. / LUT_WIDTH, -0. / LUT_HEIGHT)).rgb * (1 - LUT_data.a);
        #else
            LUT_data.rgb =
                texture2D(colortex15, texcoord + vec2(256. / LUT_WIDTH, -256. / LUT_HEIGHT)).rgb;
        #endif

    gl_FragData[0] = LUT_data;
}