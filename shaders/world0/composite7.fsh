#version 120

#define GAMMA 2.2   //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]
#define MIPMAP_LEVEL 4

uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux3;
uniform sampler2D gaux4;

uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

/* DRAWBUFFERS: 0 */
void main() {
    vec4 color_data = texture2D(gcolor, texcoord);
    vec3 color = color_data.rgb;
    float k0 = color_data.a;
    vec4 translucent_data = texture2D(composite, texcoord);
    vec3 translucent = translucent_data.rgb;
    float alpha = translucent_data.a;
    float block_id0 = texture2D(gnormal, texcoord).w;

    /* FOG SCATTER */
    vec3 fog_scatter0 = vec3(0.0);
    vec3 fog_scatter1 = vec3(0.0);
    float s = 1, alpha_scatter = 0;
    for (int i = 2; i <= MIPMAP_LEVEL; i++) s *= 0.5;
    for (int i = MIPMAP_LEVEL; i >= 2; i--) {
        translucent_data = texture2D(gaux3, texcoord * s + vec2(1 - 2 * s, mod(i, 2) == 0 ? 0 : 0.75));
        fog_scatter0 += translucent_data.rgb;
        alpha_scatter += translucent_data.a;
        color_data = texture2D(gaux4, texcoord * s + vec2(1 - 2 * s, mod(i, 2) == 0 ? 0 : 0.75));
        fog_scatter0 = mix(fog_scatter0, vec3(0.0), color_data.a);
        fog_scatter1 = mix(fog_scatter1, color_data.rgb, color_data.a);
        s *= 2;
    }
    fog_scatter0 = mix(fog_scatter0, vec3(0.0), k0);
    fog_scatter1 = mix(fog_scatter1, vec3(0.0), k0);

    color = color * (1 - alpha) + fog_scatter1 * (1 - alpha_scatter) + translucent + fog_scatter0;

    gl_FragData[0] = vec4(color, 1.0);
}