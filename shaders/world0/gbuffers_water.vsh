#version 120

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;

varying float block_id;

attribute vec4 mc_Entity;

void main() {
    gl_Position = ftransform();
    color = gl_Color.rgb;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
    block_id = mc_Entity.x > 9999 ? -1 : -2;
}