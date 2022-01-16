#version 120

uniform vec3 shadowLightPosition;

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;

void main() {
    gl_Position = ftransform();
    color = gl_Color.rgb;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    normal = 10 * shadowLightPosition;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
}