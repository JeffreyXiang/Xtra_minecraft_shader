#version 120

#define PI 3.1415926535898

#define LUT_WIDTH 512
#define LUT_HEIGHT 512

uniform sampler2D colortex15;

varying vec2 texcoord;

/* RENDERTARGETS: 15 */
void main() {
    /* LUT SKY LIGHT */
    vec4 LUT_data = texture2D(colortex15, texcoord);

    if (texcoord.s > 0. / LUT_WIDTH && texcoord.s < 256. / LUT_WIDTH && texcoord.t > 128. / LUT_HEIGHT && texcoord.t < 256. / LUT_HEIGHT)
        LUT_data = texture2D(colortex15, texcoord + vec2(256. / LUT_HEIGHT, 0));

    gl_FragData[0] = LUT_data;
}