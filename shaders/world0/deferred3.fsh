#version 120

#define PI 3.1415926535898

#define LUT_WIDTH 512
#define LUT_HEIGHT 512

uniform sampler2D colortex15;

const bool colortex15MipmapEnabled = true;

varying vec2 texcoord;

/* RENDERTARGETS: 15 */
void main() {
    /* LUT SKY LIGHT */
    vec4 LUT_data = texture2D(colortex15, texcoord);

    if (texcoord.s > 32. / LUT_WIDTH && texcoord.s < 33. / LUT_WIDTH && texcoord.t > 67. / LUT_HEIGHT && texcoord.t < 68. / LUT_HEIGHT)
        LUT_data = texture2DLod(colortex15, vec2(128. / LUT_WIDTH, 448. / LUT_HEIGHT), 7);

    gl_FragData[0] = LUT_data;
}