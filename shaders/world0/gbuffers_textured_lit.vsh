#version 120

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;

varying float blockId;

attribute vec4 mc_Entity;

void main() {
    gl_Position = ftransform();
    color = gl_Color.rgb;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    normal = gl_NormalMatrix * gl_Normal.xyz;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
    blockId = mc_Entity.x;
}