import struct
import numpy as np
import imageio

data = np.zeros((128, 128, 128))

import clouds_taichi as clouds
data[:, :, :] = clouds.perlin_noise_np

img = np.array(data[:, :, 0])
img = img * 255
img = img.astype(np.uint8)
imageio.imwrite('./utils/noise.png', img)

data = list(data.reshape(-1))

with open('./utils/noise.bin', 'wb') as fout:
    fout.write(struct.pack('f'*len(data), *data))
