#version 120

varying vec3 color;
varying vec2 texcoord;
varying vec3 normal;
varying vec2 lightMapCoord;
varying float block_id;
varying vec3 motion;

attribute vec4 mc_Entity;
attribute vec3 at_velocity;

void main() {
    gl_Position = ftransform();
    color = gl_Color.rgb;
    color *= (abs(gl_Normal.x) == 1 ? 5./3.*0.9 : 1) * (abs(gl_Normal.z) == 1 ? 5./4.*0.95 : 1);
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    normal = gl_NormalMatrix * gl_Normal.xyz;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
    block_id = mc_Entity.x > 9999 ? 2 : 1;
    motion = at_velocity;
}