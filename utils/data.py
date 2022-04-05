import struct
import numpy as np
import imageio

data = np.zeros((256, 256, 4))

''' COLOR TEMPERATURE '''
with open('./utils/color_temperature.txt', 'r') as fin:
    lines = fin.readlines()

color_temperature_data = []
for line in lines:
    if '10deg' in line:
        color_temperature_data.append([float(i) for i in line.split()[6:9]] + [1])

data[0, :len(color_temperature_data)] = np.array(color_temperature_data)

''' WATER ABSORPTION '''
water_absorption_data = imageio.imread('./utils/water_absorption.png')
data[1, :water_absorption_data.shape[1]] = (water_absorption_data / 255.) ** (2.2)

''' WATER SCATTERING '''
water_scattering_data = imageio.imread('./utils/water_scattering.png')
data[2, :water_scattering_data.shape[1]] = (water_scattering_data / 255.) ** (2.2)

img = np.array(data)
img = img * 255
img = img.astype(np.uint8)
imageio.imwrite('./utils/data.png', img)

data = list(data.reshape(-1))
print(data)

with open('./utils/data.bin', 'wb') as fout:
    fout.write(struct.pack('f'*len(data), *data))
