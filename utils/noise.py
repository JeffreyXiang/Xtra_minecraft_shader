import struct
import numpy as np
import imageio

import clouds_taichi as clouds


data = np.zeros((128, 128, 128))
data[:, :, :] = clouds.noise_3d_np

img = np.array(data[:, :, 0])
img = img * 255
img = img.astype(np.uint8)
imageio.imwrite('./utils/noise3d.png', img)

data = list(data.reshape(-1))

with open('./utils/noise3d.bin', 'wb') as fout:
    fout.write(struct.pack('f'*len(data), *data))


data = np.zeros((32, 32, 32))
data[:, :, :] = clouds.noise_3d_np_small

img = np.array(data[:, :, 0])
img = img * 255
img = img.astype(np.uint8)
imageio.imwrite('./utils/noise3d_2.png', img)

data = list(data.reshape(-1))

with open('./utils/noise3d_2.bin', 'wb') as fout:
    fout.write(struct.pack('f'*len(data), *data))


data = np.zeros((512, 512, 2))
data[:, :] = clouds.noise_2d_np

img = np.array(data[:, :])
img = np.concatenate([data, np.zeros((512, 512, 1))], axis=-1)
img = img * 255
img = img.astype(np.uint8)
imageio.imwrite('./utils/noise2d.png', img[:,:])

data = list(data.reshape(-1))

with open('./utils/noise2d.bin', 'wb') as fout:
    fout.write(struct.pack('f'*len(data), *data))
