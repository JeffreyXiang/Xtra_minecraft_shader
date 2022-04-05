#version 120

varying vec3 color;
varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    color = gl_Color.rgb;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
}