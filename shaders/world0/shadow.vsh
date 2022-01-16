#version 120
 
#define SHADOW_FISHEY_LENS_STRENGTH 0.85
 
varying vec2 texcoord;

vec2 fish_len_distortion(vec2 ndc_coord_xy) {
    float dist = length(ndc_coord_xy);
    float distort = (1.0 - SHADOW_FISHEY_LENS_STRENGTH ) + dist * SHADOW_FISHEY_LENS_STRENGTH;
    return ndc_coord_xy.xy / distort;
}
 
void main() {
    gl_Position = ftransform();
    gl_Position.xy = fish_len_distortion(gl_Position.xy);
    
    texcoord = gl_MultiTexCoord0.xy;
}