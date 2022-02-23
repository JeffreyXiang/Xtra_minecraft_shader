#version 120

uniform sampler2D colortex8;

const bool colortex8MipmapEnabled = true;

varying vec2 texcoord;

/* DRAWBUFFERS: 8 */
void main() {
    vec4 bloom_color = vec4(0.0);
    vec2 tex_coord;
    float s = 1;
    for (int i = 2; i < 8; i++) {
        tex_coord = texcoord - vec2(1 - s, mod(i, 2) == 0 ? 0 : 0.75);
        s *= 0.5;
        if (tex_coord.s > 0 && tex_coord.s < s && tex_coord.t > 0 && tex_coord.t < s) {
            bloom_color = texture2D(colortex8, tex_coord / s);
            break;
        }
        if (tex_coord.s < s) break;
    }

    
    gl_FragData[0] = bloom_color;
}