#version 120

#define TAA_ENABLE 1 // [0 1]

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

const float Halton2[] = float[](1./2, 1./4, 3./4, 1./8, 5./8, 3./8, 7./8, 1./16);
const float Halton3[] = float[](1./3, 2./3, 1./9, 4./9, 7./9, 2./9, 5./9, 8./9);

void main() {
    gl_Position = ftransform();
#if TAA_ENABLE
    int idx = int(mod(frameCounter, 8));
    gl_Position.xy += vec2((Halton2[idx] * 2 - 1) * gl_Position.w / viewWidth, (Halton3[idx] * 2 - 1) * gl_Position.w / viewHeight);
#endif
    color = gl_Color.rgb;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    normal = gl_NormalMatrix * gl_Normal.xyz;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
}