#version 120

uniform sampler2D composite;

const bool compositeMipmapEnabled = true;

varying vec2 texcoord;

/* DRAWBUFFERS: 3 */
void main() {
    vec4 bloom_color = vec4(0.0);
    vec2 tex_coord;
    float s = 1;
    for (int i = 2; i < 8; i++) {
        tex_coord = texcoord - 1 + s;
        s *= 0.5;
        if (tex_coord.s > 0 && tex_coord.s < s && tex_coord.t > 0 && tex_coord.t < s) {
            bloom_color = texture2D(composite, tex_coord / s);
            break;
        }
        if (tex_coord.s < s || tex_coord.t < s) break;
    }

    
    gl_FragData[0] = bloom_color;
}