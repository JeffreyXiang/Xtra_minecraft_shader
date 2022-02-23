#version 120

#define MIPMAP_LEVEL 4

uniform sampler2D gcolor;
uniform sampler2D composite;
uniform sampler2D gaux3;
uniform sampler2D gaux4;

const bool gaux3MipmapEnabled = true;
const bool gaux4MipmapEnabled = true;

varying vec2 texcoord;

/* DRAWBUFFERS: 0367 */
void main() {
    vec4 color = vec4(texture2D(gcolor, texcoord).rgb, 0.0);
    vec4 translucent = texture2D(composite, texcoord);
    vec4 fog_data0 = vec4(0.0);
    vec4 fog_data1 = vec4(0.0);
    vec2 tex_coord;

    fog_data0 = texture2D(gaux3, texcoord);
    fog_data1 = texture2D(gaux4, texcoord);
    float fog_decay0 = fog_data0.a;
    float fog_decay1 = fog_data1.a;
    fog_decay0 = (1 - fog_decay0) * (1 - fog_decay0);
    fog_decay1 = (1 - fog_decay1) * (1 - fog_decay1);
    if (fog_decay0 < 1. / (MIPMAP_LEVEL - 1)) {
        translucent.rgb += fog_data0.rgb * (1 - fog_decay0 * (MIPMAP_LEVEL - 1));
    }
    if (fog_decay1 < 1. / (MIPMAP_LEVEL - 1)) {
        color.w = 1 - fog_decay1 * (MIPMAP_LEVEL - 1);
        color.rgb += fog_data1.rgb * color.w;
    }

    fog_data0 = vec4(0.0);
    fog_data1 = vec4(0.0);
    float s = 1;
    for (int i = 2; i <= MIPMAP_LEVEL; i++) {
        tex_coord = texcoord - vec2(1 - s, mod(i, 2) == 0 ? 0 : 0.75);
        s *= 0.5;
        if (tex_coord.s > 0 && tex_coord.s < s && tex_coord.t > 0 && tex_coord.t < s) {
            fog_data0 = texture2D(gaux3, tex_coord / s);
            fog_data1 = texture2D(gaux4, tex_coord / s);
            float alpha = texture2D(composite, tex_coord / s).a;
            float fog_decay0 = fog_data0.a;
            float fog_decay1 = fog_data1.a;
            fog_data0.a = alpha;
            float k0, s0, k1, s1;
            int i0 = 1, i1 = 1;
            fog_decay0 = (1 - fog_decay0) * (1 - fog_decay0);
            fog_decay1 = (1 - fog_decay1) * (1 - fog_decay1);
            s0 = s1 = i0 = i1 = 1;
            for (int i = 2; i <= MIPMAP_LEVEL; i++) {
                float thres = float(i - 1) / (MIPMAP_LEVEL - 1);
                if (fog_decay0 > thres) {s0 *= 0.5; k0 = thres; i0 = i;}
                if (fog_decay1 > thres) {s1 *= 0.5; k1 = thres; i1 = i;}
            }
            k0 = 1 - (fog_decay0 - k0) * (MIPMAP_LEVEL - 1);
            k1 = 1 - (fog_decay1 - k1) * (MIPMAP_LEVEL - 1);
            fog_data0 *= i == i0 ? k0 : i == i0 + 1 ? 1 - k0 : 0;
            fog_data1.a = i == i1 ? k1 : i > i1 ? 1 : 0;
            break;
        }
        if (tex_coord.s < s) break;
    }

    gl_FragData[0] = color;
    gl_FragData[1] = translucent;
    gl_FragData[2] = fog_data0;
    gl_FragData[3] = fog_data1;
}