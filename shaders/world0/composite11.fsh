#version 120

#define BLOOM_ENABLE 1 // [0 1]
#define DOF_ENABLE 1 // [0 1]

#define GAUSSIAN_KERNEL_SIZE 9
#define GAUSSIAN_KERNEL_STRIDE 1

uniform sampler2D gnormal;
uniform sampler2D gaux2;
uniform sampler2D colortex8;

uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

vec2 offset(vec2 ori) {
    return vec2(ori.x * GAUSSIAN_KERNEL_STRIDE / viewWidth, ori.y * GAUSSIAN_KERNEL_STRIDE / viewHeight);
}

/* RENDERTARGETS: 2,5,8 */
void main() {
    /* GAUSSIAN HORIZONTAL */
    #if DOF_ENABLE
    #if GAUSSIAN_KERNEL_SIZE == 3
    vec4 dof_color =
        texture2D(gnormal, texcoord + offset(vec2(0, -1))) * 0.250000 +
        texture2D(gnormal, texcoord + offset(vec2(0, 0))) * 0.500000 +
        texture2D(gnormal, texcoord + offset(vec2(0, 1))) * 0.250000;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 5
    vec4 dof_color =
        texture2D(gnormal, texcoord + offset(vec2(0, -2))) * 0.062500 +
        texture2D(gnormal, texcoord + offset(vec2(0, -1))) * 0.250000 +
        texture2D(gnormal, texcoord + offset(vec2(0, 0))) * 0.375000 +
        texture2D(gnormal, texcoord + offset(vec2(0, 1))) * 0.250000 +
        texture2D(gnormal, texcoord + offset(vec2(0, 2))) * 0.062500;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 7
    vec4 dof_color =
        texture2D(gnormal, texcoord + offset(vec2(0, -3))) * 0.031250 +
        texture2D(gnormal, texcoord + offset(vec2(0, -2))) * 0.109375 +
        texture2D(gnormal, texcoord + offset(vec2(0, -1))) * 0.218750 +
        texture2D(gnormal, texcoord + offset(vec2(0, 0))) * 0.281250 +
        texture2D(gnormal, texcoord + offset(vec2(0, 1))) * 0.218750 +
        texture2D(gnormal, texcoord + offset(vec2(0, 2))) * 0.109375 +
        texture2D(gnormal, texcoord + offset(vec2(0, 3))) * 0.031250;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 9
    vec4 dof_color =
        texture2D(gnormal, texcoord + offset(vec2(0, -4))) * 0.015625 +
        texture2D(gnormal, texcoord + offset(vec2(0, -3))) * 0.050781 +
        texture2D(gnormal, texcoord + offset(vec2(0, -2))) * 0.117188 +
        texture2D(gnormal, texcoord + offset(vec2(0, -1))) * 0.199219 +
        texture2D(gnormal, texcoord + offset(vec2(0, 0))) * 0.234375 +
        texture2D(gnormal, texcoord + offset(vec2(0, 1))) * 0.199219 +
        texture2D(gnormal, texcoord + offset(vec2(0, 2))) * 0.117188 +
        texture2D(gnormal, texcoord + offset(vec2(0, 3))) * 0.050781 +
        texture2D(gnormal, texcoord + offset(vec2(0, 4))) * 0.015625;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 11
    vec4 dof_color =
        texture2D(gnormal, texcoord + offset(vec2(0, -5))) * 0.008812 +
        texture2D(gnormal, texcoord + offset(vec2(0, -4))) * 0.027144 +
        texture2D(gnormal, texcoord + offset(vec2(0, -3))) * 0.065114 +
        texture2D(gnormal, texcoord + offset(vec2(0, -2))) * 0.121649 +
        texture2D(gnormal, texcoord + offset(vec2(0, -1))) * 0.176998 +
        texture2D(gnormal, texcoord + offset(vec2(0, 0))) * 0.200565 +
        texture2D(gnormal, texcoord + offset(vec2(0, 1))) * 0.176998 +
        texture2D(gnormal, texcoord + offset(vec2(0, 2))) * 0.121649 +
        texture2D(gnormal, texcoord + offset(vec2(0, 3))) * 0.065114 +
        texture2D(gnormal, texcoord + offset(vec2(0, 4))) * 0.027144 +
        texture2D(gnormal, texcoord + offset(vec2(0, 5))) * 0.008812;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 13
    vec4 dof_color =
        texture2D(gnormal, texcoord + offset(vec2(0, -6))) * 0.005799 +
        texture2D(gnormal, texcoord + offset(vec2(0, -5))) * 0.016401 +
        texture2D(gnormal, texcoord + offset(vec2(0, -4))) * 0.038399 +
        texture2D(gnormal, texcoord + offset(vec2(0, -3))) * 0.074414 +
        texture2D(gnormal, texcoord + offset(vec2(0, -2))) * 0.119371 +
        texture2D(gnormal, texcoord + offset(vec2(0, -1))) * 0.158506 +
        texture2D(gnormal, texcoord + offset(vec2(0, 0))) * 0.174219 +
        texture2D(gnormal, texcoord + offset(vec2(0, 1))) * 0.158506 +
        texture2D(gnormal, texcoord + offset(vec2(0, 2))) * 0.119371 +
        texture2D(gnormal, texcoord + offset(vec2(0, 3))) * 0.074414 +
        texture2D(gnormal, texcoord + offset(vec2(0, 4))) * 0.038399 +
        texture2D(gnormal, texcoord + offset(vec2(0, 5))) * 0.016401 +
        texture2D(gnormal, texcoord + offset(vec2(0, 6))) * 0.005799;
    #endif
    
    gl_FragData[0] = dof_color;

    #if GAUSSIAN_KERNEL_SIZE == 3
    vec4 dof_color_g =
        texture2D(gaux2, texcoord + offset(vec2(0, -1))) * 0.250000 +
        texture2D(gaux2, texcoord + offset(vec2(0, 0))) * 0.500000 +
        texture2D(gaux2, texcoord + offset(vec2(0, 1))) * 0.250000;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 5
    vec4 dof_color_g =
        texture2D(gaux2, texcoord + offset(vec2(0, -2))) * 0.062500 +
        texture2D(gaux2, texcoord + offset(vec2(0, -1))) * 0.250000 +
        texture2D(gaux2, texcoord + offset(vec2(0, 0))) * 0.375000 +
        texture2D(gaux2, texcoord + offset(vec2(0, 1))) * 0.250000 +
        texture2D(gaux2, texcoord + offset(vec2(0, 2))) * 0.062500;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 7
    vec4 dof_color_g =
        texture2D(gaux2, texcoord + offset(vec2(0, -3))) * 0.031250 +
        texture2D(gaux2, texcoord + offset(vec2(0, -2))) * 0.109375 +
        texture2D(gaux2, texcoord + offset(vec2(0, -1))) * 0.218750 +
        texture2D(gaux2, texcoord + offset(vec2(0, 0))) * 0.281250 +
        texture2D(gaux2, texcoord + offset(vec2(0, 1))) * 0.218750 +
        texture2D(gaux2, texcoord + offset(vec2(0, 2))) * 0.109375 +
        texture2D(gaux2, texcoord + offset(vec2(0, 3))) * 0.031250;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 9
    vec4 dof_color_g =
        texture2D(gaux2, texcoord + offset(vec2(0, -4))) * 0.015625 +
        texture2D(gaux2, texcoord + offset(vec2(0, -3))) * 0.050781 +
        texture2D(gaux2, texcoord + offset(vec2(0, -2))) * 0.117188 +
        texture2D(gaux2, texcoord + offset(vec2(0, -1))) * 0.199219 +
        texture2D(gaux2, texcoord + offset(vec2(0, 0))) * 0.234375 +
        texture2D(gaux2, texcoord + offset(vec2(0, 1))) * 0.199219 +
        texture2D(gaux2, texcoord + offset(vec2(0, 2))) * 0.117188 +
        texture2D(gaux2, texcoord + offset(vec2(0, 3))) * 0.050781 +
        texture2D(gaux2, texcoord + offset(vec2(0, 4))) * 0.015625;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 11
    vec4 dof_color_g =
        texture2D(gaux2, texcoord + offset(vec2(0, -5))) * 0.008812 +
        texture2D(gaux2, texcoord + offset(vec2(0, -4))) * 0.027144 +
        texture2D(gaux2, texcoord + offset(vec2(0, -3))) * 0.065114 +
        texture2D(gaux2, texcoord + offset(vec2(0, -2))) * 0.121649 +
        texture2D(gaux2, texcoord + offset(vec2(0, -1))) * 0.176998 +
        texture2D(gaux2, texcoord + offset(vec2(0, 0))) * 0.200565 +
        texture2D(gaux2, texcoord + offset(vec2(0, 1))) * 0.176998 +
        texture2D(gaux2, texcoord + offset(vec2(0, 2))) * 0.121649 +
        texture2D(gaux2, texcoord + offset(vec2(0, 3))) * 0.065114 +
        texture2D(gaux2, texcoord + offset(vec2(0, 4))) * 0.027144 +
        texture2D(gaux2, texcoord + offset(vec2(0, 5))) * 0.008812;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 13
    vec4 dof_color_g =
        texture2D(gaux2, texcoord + offset(vec2(0, -6))) * 0.005799 +
        texture2D(gaux2, texcoord + offset(vec2(0, -5))) * 0.016401 +
        texture2D(gaux2, texcoord + offset(vec2(0, -4))) * 0.038399 +
        texture2D(gaux2, texcoord + offset(vec2(0, -3))) * 0.074414 +
        texture2D(gaux2, texcoord + offset(vec2(0, -2))) * 0.119371 +
        texture2D(gaux2, texcoord + offset(vec2(0, -1))) * 0.158506 +
        texture2D(gaux2, texcoord + offset(vec2(0, 0))) * 0.174219 +
        texture2D(gaux2, texcoord + offset(vec2(0, 1))) * 0.158506 +
        texture2D(gaux2, texcoord + offset(vec2(0, 2))) * 0.119371 +
        texture2D(gaux2, texcoord + offset(vec2(0, 3))) * 0.074414 +
        texture2D(gaux2, texcoord + offset(vec2(0, 4))) * 0.038399 +
        texture2D(gaux2, texcoord + offset(vec2(0, 5))) * 0.016401 +
        texture2D(gaux2, texcoord + offset(vec2(0, 6))) * 0.005799;
    #endif
    
    gl_FragData[1] = dof_color_g;
    #endif

    #if BLOOM_ENABLE
    #if GAUSSIAN_KERNEL_SIZE == 3
    vec4 bloom_color =
        texture2D(colortex8, texcoord + offset(vec2(0, -1))) * 0.250000 +
        texture2D(colortex8, texcoord + offset(vec2(0, 0))) * 0.500000 +
        texture2D(colortex8, texcoord + offset(vec2(0, 1))) * 0.250000;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 5
    vec4 bloom_color =
        texture2D(colortex8, texcoord + offset(vec2(0, -2))) * 0.062500 +
        texture2D(colortex8, texcoord + offset(vec2(0, -1))) * 0.250000 +
        texture2D(colortex8, texcoord + offset(vec2(0, 0))) * 0.375000 +
        texture2D(colortex8, texcoord + offset(vec2(0, 1))) * 0.250000 +
        texture2D(colortex8, texcoord + offset(vec2(0, 2))) * 0.062500;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 7
    vec4 bloom_color =
        texture2D(colortex8, texcoord + offset(vec2(0, -3))) * 0.031250 +
        texture2D(colortex8, texcoord + offset(vec2(0, -2))) * 0.109375 +
        texture2D(colortex8, texcoord + offset(vec2(0, -1))) * 0.218750 +
        texture2D(colortex8, texcoord + offset(vec2(0, 0))) * 0.281250 +
        texture2D(colortex8, texcoord + offset(vec2(0, 1))) * 0.218750 +
        texture2D(colortex8, texcoord + offset(vec2(0, 2))) * 0.109375 +
        texture2D(colortex8, texcoord + offset(vec2(0, 3))) * 0.031250;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 9
    vec4 bloom_color =
        texture2D(colortex8, texcoord + offset(vec2(0, -4))) * 0.015625 +
        texture2D(colortex8, texcoord + offset(vec2(0, -3))) * 0.050781 +
        texture2D(colortex8, texcoord + offset(vec2(0, -2))) * 0.117188 +
        texture2D(colortex8, texcoord + offset(vec2(0, -1))) * 0.199219 +
        texture2D(colortex8, texcoord + offset(vec2(0, 0))) * 0.234375 +
        texture2D(colortex8, texcoord + offset(vec2(0, 1))) * 0.199219 +
        texture2D(colortex8, texcoord + offset(vec2(0, 2))) * 0.117188 +
        texture2D(colortex8, texcoord + offset(vec2(0, 3))) * 0.050781 +
        texture2D(colortex8, texcoord + offset(vec2(0, 4))) * 0.015625;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 11
    vec4 bloom_color =
        texture2D(colortex8, texcoord + offset(vec2(0, -5))) * 0.008812 +
        texture2D(colortex8, texcoord + offset(vec2(0, -4))) * 0.027144 +
        texture2D(colortex8, texcoord + offset(vec2(0, -3))) * 0.065114 +
        texture2D(colortex8, texcoord + offset(vec2(0, -2))) * 0.121649 +
        texture2D(colortex8, texcoord + offset(vec2(0, -1))) * 0.176998 +
        texture2D(colortex8, texcoord + offset(vec2(0, 0))) * 0.200565 +
        texture2D(colortex8, texcoord + offset(vec2(0, 1))) * 0.176998 +
        texture2D(colortex8, texcoord + offset(vec2(0, 2))) * 0.121649 +
        texture2D(colortex8, texcoord + offset(vec2(0, 3))) * 0.065114 +
        texture2D(colortex8, texcoord + offset(vec2(0, 4))) * 0.027144 +
        texture2D(colortex8, texcoord + offset(vec2(0, 5))) * 0.008812;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 13
    vec4 bloom_color =
        texture2D(colortex8, texcoord + offset(vec2(0, -6))) * 0.005799 +
        texture2D(colortex8, texcoord + offset(vec2(0, -5))) * 0.016401 +
        texture2D(colortex8, texcoord + offset(vec2(0, -4))) * 0.038399 +
        texture2D(colortex8, texcoord + offset(vec2(0, -3))) * 0.074414 +
        texture2D(colortex8, texcoord + offset(vec2(0, -2))) * 0.119371 +
        texture2D(colortex8, texcoord + offset(vec2(0, -1))) * 0.158506 +
        texture2D(colortex8, texcoord + offset(vec2(0, 0))) * 0.174219 +
        texture2D(colortex8, texcoord + offset(vec2(0, 1))) * 0.158506 +
        texture2D(colortex8, texcoord + offset(vec2(0, 2))) * 0.119371 +
        texture2D(colortex8, texcoord + offset(vec2(0, 3))) * 0.074414 +
        texture2D(colortex8, texcoord + offset(vec2(0, 4))) * 0.038399 +
        texture2D(colortex8, texcoord + offset(vec2(0, 5))) * 0.016401 +
        texture2D(colortex8, texcoord + offset(vec2(0, 6))) * 0.005799;
    #endif
    
    gl_FragData[2] = bloom_color;
    #endif
}