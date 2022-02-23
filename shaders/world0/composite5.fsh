#version 120

#define GAUSSIAN_KERNEL_SIZE 9
#define GAUSSIAN_KERNEL_STRIDE 1

uniform sampler2D gaux3;
uniform sampler2D gaux4;

uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

vec2 offset(vec2 ori) {
    return vec2(ori.x * GAUSSIAN_KERNEL_STRIDE / viewWidth, ori.y * GAUSSIAN_KERNEL_STRIDE / viewHeight);
}

/* DRAWBUFFERS: 67 */
void main() {
    /* FOG GAUSSIAN HORIZONTAL */

    #if GAUSSIAN_KERNEL_SIZE == 3
    vec4 fog_data0 =
        texture2D(gaux3, texcoord + offset(vec2(-1, 0))) * 0.250000 +
        texture2D(gaux3, texcoord + offset(vec2(0, 0))) * 0.500000 +
        texture2D(gaux3, texcoord + offset(vec2(1, 0))) * 0.250000;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 5
    vec4 fog_data0 =
        texture2D(gaux3, texcoord + offset(vec2(-2, 0))) * 0.062500 +
        texture2D(gaux3, texcoord + offset(vec2(-1, 0))) * 0.250000 +
        texture2D(gaux3, texcoord + offset(vec2(0, 0))) * 0.375000 +
        texture2D(gaux3, texcoord + offset(vec2(1, 0))) * 0.250000 +
        texture2D(gaux3, texcoord + offset(vec2(2, 0))) * 0.062500;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 7
    vec4 fog_data0 =
        texture2D(gaux3, texcoord + offset(vec2(-3, 0))) * 0.031250 +
        texture2D(gaux3, texcoord + offset(vec2(-2, 0))) * 0.109375 +
        texture2D(gaux3, texcoord + offset(vec2(-1, 0))) * 0.218750 +
        texture2D(gaux3, texcoord + offset(vec2(0, 0))) * 0.281250 +
        texture2D(gaux3, texcoord + offset(vec2(1, 0))) * 0.218750 +
        texture2D(gaux3, texcoord + offset(vec2(2, 0))) * 0.109375 +
        texture2D(gaux3, texcoord + offset(vec2(3, 0))) * 0.031250;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 9
    vec4 fog_data0 =
        texture2D(gaux3, texcoord + offset(vec2(-4, 0))) * 0.015625 +
        texture2D(gaux3, texcoord + offset(vec2(-3, 0))) * 0.050781 +
        texture2D(gaux3, texcoord + offset(vec2(-2, 0))) * 0.117188 +
        texture2D(gaux3, texcoord + offset(vec2(-1, 0))) * 0.199219 +
        texture2D(gaux3, texcoord + offset(vec2(0, 0))) * 0.234375 +
        texture2D(gaux3, texcoord + offset(vec2(1, 0))) * 0.199219 +
        texture2D(gaux3, texcoord + offset(vec2(2, 0))) * 0.117188 +
        texture2D(gaux3, texcoord + offset(vec2(3, 0))) * 0.050781 +
        texture2D(gaux3, texcoord + offset(vec2(4, 0))) * 0.015625;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 11
    vec4 fog_data0 =
        texture2D(gaux3, texcoord + offset(vec2(-5, 0))) * 0.008812 +
        texture2D(gaux3, texcoord + offset(vec2(-4, 0))) * 0.027144 +
        texture2D(gaux3, texcoord + offset(vec2(-3, 0))) * 0.065114 +
        texture2D(gaux3, texcoord + offset(vec2(-2, 0))) * 0.121649 +
        texture2D(gaux3, texcoord + offset(vec2(-1, 0))) * 0.176998 +
        texture2D(gaux3, texcoord + offset(vec2(0, 0))) * 0.200565 +
        texture2D(gaux3, texcoord + offset(vec2(1, 0))) * 0.176998 +
        texture2D(gaux3, texcoord + offset(vec2(2, 0))) * 0.121649 +
        texture2D(gaux3, texcoord + offset(vec2(3, 0))) * 0.065114 +
        texture2D(gaux3, texcoord + offset(vec2(4, 0))) * 0.027144 +
        texture2D(gaux3, texcoord + offset(vec2(5, 0))) * 0.008812;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 13
    vec4 fog_data0 =
        texture2D(gaux3, texcoord + offset(vec2(-6, 0))) * 0.005799 +
        texture2D(gaux3, texcoord + offset(vec2(-5, 0))) * 0.016401 +
        texture2D(gaux3, texcoord + offset(vec2(-4, 0))) * 0.038399 +
        texture2D(gaux3, texcoord + offset(vec2(-3, 0))) * 0.074414 +
        texture2D(gaux3, texcoord + offset(vec2(-2, 0))) * 0.119371 +
        texture2D(gaux3, texcoord + offset(vec2(-1, 0))) * 0.158506 +
        texture2D(gaux3, texcoord + offset(vec2(0, 0))) * 0.174219 +
        texture2D(gaux3, texcoord + offset(vec2(1, 0))) * 0.158506 +
        texture2D(gaux3, texcoord + offset(vec2(2, 0))) * 0.119371 +
        texture2D(gaux3, texcoord + offset(vec2(3, 0))) * 0.074414 +
        texture2D(gaux3, texcoord + offset(vec2(4, 0))) * 0.038399 +
        texture2D(gaux3, texcoord + offset(vec2(5, 0))) * 0.016401 +
        texture2D(gaux3, texcoord + offset(vec2(6, 0))) * 0.005799;
    #endif

    #if GAUSSIAN_KERNEL_SIZE == 3
    vec4 fog_data1 =
        texture2D(gaux4, texcoord + offset(vec2(-1, 0))) * 0.250000 +
        texture2D(gaux4, texcoord + offset(vec2(0, 0))) * 0.500000 +
        texture2D(gaux4, texcoord + offset(vec2(1, 0))) * 0.250000;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 5
    vec4 fog_data1 =
        texture2D(gaux4, texcoord + offset(vec2(-2, 0))) * 0.062500 +
        texture2D(gaux4, texcoord + offset(vec2(-1, 0))) * 0.250000 +
        texture2D(gaux4, texcoord + offset(vec2(0, 0))) * 0.375000 +
        texture2D(gaux4, texcoord + offset(vec2(1, 0))) * 0.250000 +
        texture2D(gaux4, texcoord + offset(vec2(2, 0))) * 0.062500;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 7
    vec4 fog_data1 =
        texture2D(gaux4, texcoord + offset(vec2(-3, 0))) * 0.031250 +
        texture2D(gaux4, texcoord + offset(vec2(-2, 0))) * 0.109375 +
        texture2D(gaux4, texcoord + offset(vec2(-1, 0))) * 0.218750 +
        texture2D(gaux4, texcoord + offset(vec2(0, 0))) * 0.281250 +
        texture2D(gaux4, texcoord + offset(vec2(1, 0))) * 0.218750 +
        texture2D(gaux4, texcoord + offset(vec2(2, 0))) * 0.109375 +
        texture2D(gaux4, texcoord + offset(vec2(3, 0))) * 0.031250;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 9
    vec4 fog_data1 =
        texture2D(gaux4, texcoord + offset(vec2(-4, 0))) * 0.015625 +
        texture2D(gaux4, texcoord + offset(vec2(-3, 0))) * 0.050781 +
        texture2D(gaux4, texcoord + offset(vec2(-2, 0))) * 0.117188 +
        texture2D(gaux4, texcoord + offset(vec2(-1, 0))) * 0.199219 +
        texture2D(gaux4, texcoord + offset(vec2(0, 0))) * 0.234375 +
        texture2D(gaux4, texcoord + offset(vec2(1, 0))) * 0.199219 +
        texture2D(gaux4, texcoord + offset(vec2(2, 0))) * 0.117188 +
        texture2D(gaux4, texcoord + offset(vec2(3, 0))) * 0.050781 +
        texture2D(gaux4, texcoord + offset(vec2(4, 0))) * 0.015625;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 11
    vec4 fog_data1 =
        texture2D(gaux4, texcoord + offset(vec2(-5, 0))) * 0.008812 +
        texture2D(gaux4, texcoord + offset(vec2(-4, 0))) * 0.027144 +
        texture2D(gaux4, texcoord + offset(vec2(-3, 0))) * 0.065114 +
        texture2D(gaux4, texcoord + offset(vec2(-2, 0))) * 0.121649 +
        texture2D(gaux4, texcoord + offset(vec2(-1, 0))) * 0.176998 +
        texture2D(gaux4, texcoord + offset(vec2(0, 0))) * 0.200565 +
        texture2D(gaux4, texcoord + offset(vec2(1, 0))) * 0.176998 +
        texture2D(gaux4, texcoord + offset(vec2(2, 0))) * 0.121649 +
        texture2D(gaux4, texcoord + offset(vec2(3, 0))) * 0.065114 +
        texture2D(gaux4, texcoord + offset(vec2(4, 0))) * 0.027144 +
        texture2D(gaux4, texcoord + offset(vec2(5, 0))) * 0.008812;
    #endif
    #if GAUSSIAN_KERNEL_SIZE == 13
    vec4 fog_data1 =
        texture2D(gaux4, texcoord + offset(vec2(-6, 0))) * 0.005799 +
        texture2D(gaux4, texcoord + offset(vec2(-5, 0))) * 0.016401 +
        texture2D(gaux4, texcoord + offset(vec2(-4, 0))) * 0.038399 +
        texture2D(gaux4, texcoord + offset(vec2(-3, 0))) * 0.074414 +
        texture2D(gaux4, texcoord + offset(vec2(-2, 0))) * 0.119371 +
        texture2D(gaux4, texcoord + offset(vec2(-1, 0))) * 0.158506 +
        texture2D(gaux4, texcoord + offset(vec2(0, 0))) * 0.174219 +
        texture2D(gaux4, texcoord + offset(vec2(1, 0))) * 0.158506 +
        texture2D(gaux4, texcoord + offset(vec2(2, 0))) * 0.119371 +
        texture2D(gaux4, texcoord + offset(vec2(3, 0))) * 0.074414 +
        texture2D(gaux4, texcoord + offset(vec2(4, 0))) * 0.038399 +
        texture2D(gaux4, texcoord + offset(vec2(5, 0))) * 0.016401 +
        texture2D(gaux4, texcoord + offset(vec2(6, 0))) * 0.005799;
    #endif
    
    gl_FragData[0] = fog_data0;
    gl_FragData[1] = fog_data1;
}