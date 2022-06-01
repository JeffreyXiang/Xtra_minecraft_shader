#version 120

#define PI 3.1415926535898

#define LUT_WIDTH 512
#define LUT_HEIGHT 512

uniform sampler2D colortex15;

varying vec2 texcoord;

/* RENDERTARGETS: 15 */
void main() {
    /* LUTS */
    vec4 LUT_data = vec4(0.0);
    vec2 LUT_texcoord = vec2(texcoord.x / 256 * LUT_WIDTH, texcoord.y / 256 * LUT_HEIGHT);
    if (LUT_texcoord.x < 1 && LUT_texcoord.y < 1)
        LUT_data = texture2D(colortex15, LUT_texcoord);

    gl_FragData[0] = LUT_data;
}