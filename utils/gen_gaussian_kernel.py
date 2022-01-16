import cv2

buffer = 'composite'
arg = 'bloom_color'
horizontal = False

with open('gaussian_script.txt', 'w') as f:
    for size in range(3, 100, 2):
        f.write(f'    #if GAUSSIAN_KERNEL_SIZE == {size}\n')
        f.write(f'    vec4 {arg} =\n')
        for i, val in enumerate(cv2.getGaussianKernel(size, -1).squeeze()):
            if horizontal:
                f.write(f'        texture2D({buffer}, texcoord + offset(vec2({i - size // 2}, 0))) * {val:.6f}' + (';' if i == size - 1 else ' +') + '\n')
            else:
                f.write(f'        texture2D({buffer}, texcoord + offset(vec2(0, {i - size // 2}))) * {val:.6f}' + (';' if i == size - 1 else ' +') + '\n')
        f.write('    #endif\n')
