from matplotlib import pyplot as plt
import numpy as np

img = np.zeros((1, 512, 3), dtype=float)

for i in range(512):
    m_time = i / 511 * np.pi - 0.5 * np.pi
    r = 1 * (np.exp(0.001-0.001/(np.cos(0.99 * m_time))))
    g = 1 * (np.exp(0.001-0.01/(np.cos(0.99 * m_time))))
    b = 1 * (np.exp(0.001-0.03/(np.cos(0.99 * m_time))))
    img[0, i] = [r, g, b]

plt.imshow(img, aspect='auto')
plt.show()
