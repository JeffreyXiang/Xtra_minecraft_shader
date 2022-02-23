import struct
import numpy as np
import imageio

with open('./utils/color_temperature.txt', 'r') as fin:
    lines = fin.readlines()

data = []
for line in lines:
    if '10deg' in line:
        data += [float(i) for i in line.split()[6:9]]

print(data)

with open('./utils/color_temperature.bin', 'wb') as fout:
    fout.write(struct.pack('f'*len(data), *data))

img = np.array(data).reshape(1, len(data) // 3, 3)
img = img * 255
img = img.astype(np.uint8)
imageio.imwrite('./utils/color_temperature.png', img)
