import taichi as ti
import numpy as np

ti.init(arch=ti.gpu, default_fp=ti.f64)  # Try to run on GPU

vec3f = ti.types.matrix(3, 1, ti.f64)
vec2f = ti.types.matrix(2, 1, ti.f64)


def remap(v, ori_min, ori_max, new_min, new_max):
    return np.clip((v - ori_min) / (ori_max - ori_min), 0, 1) * (new_max - new_min) + new_min

@ti.func
def permin_interp(v1, v2, k):
    k = 6 * k**5 - 15 * k**4 + 10 * k**3
    return v1 * (1 - k) + v2 * k


# Perlin 2D
perlin_noise_2d = ti.field(ti.f64, shape=(512, 512))

perlin_grad_2d = vec2f.field(shape=(32))
perlin_grad_2d_np = np.array([[np.sin(theta), np.cos(theta)] for theta in np.linspace(0, 2*np.pi, 32, False)], dtype=float)
perlin_grad_2d.from_numpy(perlin_grad_2d_np)

perlin_permute_2d = ti.field(ti.i32, shape=(512, 512))

@ti.kernel
def cal_perlin_2d_ti(buffer: ti.template(), cells: ti.int32):
    cell_size = buffer.shape[0] // cells
    for i, j in buffer:
        u = (i + 0.5) / cell_size
        v = (j + 0.5) / cell_size

        l = int(ti.floor(u))
        r = int(ti.ceil(u))
        b = int(ti.floor(v))
        t = int(ti.ceil(v))

        p00 = vec2f([u - l, v - b]).dot(perlin_grad_2d[perlin_permute_2d[l%cells, b%cells]]) 
        p01 = vec2f([u - l, v - t]).dot(perlin_grad_2d[perlin_permute_2d[l%cells, t%cells]]) 
        p10 = vec2f([u - r, v - b]).dot(perlin_grad_2d[perlin_permute_2d[r%cells, b%cells]]) 
        p11 = vec2f([u - r, v - t]).dot(perlin_grad_2d[perlin_permute_2d[r%cells, t%cells]]) 

        p0 = permin_interp(p00, p01, v - b)
        p1 = permin_interp(p10, p11, v - b)

        p = permin_interp(p0, p1, u - l)
        
        buffer[i, j] = p


def cal_perlin_2d(buffer, cells=8):
    perlin_permute_2d_np = np.zeros((512, 512), dtype=int)
    perlin_permute_2d_np[:cells, :cells] = np.random.permutation(cells*cells).reshape(cells, cells) % 32
    perlin_permute_2d.from_numpy(perlin_permute_2d_np)

    cal_perlin_2d_ti(buffer, cells)

    return buffer.to_numpy() 


def cal_perlin_2d_fbm(buffer=perlin_noise_2d, cells=8, layers=4):
    perlin_noise_2d_np = None
    for i in range(1, layers+1):        
        if i == 1:
            perlin_noise_2d_np = (0.5 + 0.5**layers) * cal_perlin_2d(buffer, cells)
        else:
            perlin_noise_2d_np += 0.5**i * cal_perlin_2d(buffer, cells)
        cells *= 2
    return perlin_noise_2d_np


# Perlin 3D
perlin_noise_3d = ti.field(ti.f64, shape=(128, 128, 128))

perlin_grad_3d = vec3f.field(shape=(12))
perlin_grad_3d_np = np.array([
    [1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0],
    [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
    [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1]
], dtype=float)
perlin_grad_3d.from_numpy(perlin_grad_3d_np)

perlin_permute_3d = ti.field(ti.i32, shape=(128, 128, 128))

@ti.kernel
def cal_perlin_3d_ti(buffer: ti.template(), cells: ti.int32):
    cell_size = buffer.shape[0] // cells
    for i, j, k in buffer:
        u = (i + 0.5) / cell_size
        v = (j + 0.5) / cell_size
        w = (k + 0.5) / cell_size

        l = int(ti.floor(u))
        r = int(ti.ceil(u))
        b = int(ti.floor(v))
        t = int(ti.ceil(v))
        n = int(ti.floor(w))
        f = int(ti.ceil(w))

        p000 = vec3f([u - l, v - b, w - n]).dot(perlin_grad_3d[perlin_permute_3d[l%cells, b%cells, n%cells]]) 
        p001 = vec3f([u - l, v - b, w - f]).dot(perlin_grad_3d[perlin_permute_3d[l%cells, b%cells, f%cells]]) 
        p010 = vec3f([u - l, v - t, w - n]).dot(perlin_grad_3d[perlin_permute_3d[l%cells, t%cells, n%cells]]) 
        p011 = vec3f([u - l, v - t, w - f]).dot(perlin_grad_3d[perlin_permute_3d[l%cells, t%cells, f%cells]]) 
        p100 = vec3f([u - r, v - b, w - n]).dot(perlin_grad_3d[perlin_permute_3d[r%cells, b%cells, n%cells]]) 
        p101 = vec3f([u - r, v - b, w - f]).dot(perlin_grad_3d[perlin_permute_3d[r%cells, b%cells, f%cells]]) 
        p110 = vec3f([u - r, v - t, w - n]).dot(perlin_grad_3d[perlin_permute_3d[r%cells, t%cells, n%cells]]) 
        p111 = vec3f([u - r, v - t, w - f]).dot(perlin_grad_3d[perlin_permute_3d[r%cells, t%cells, f%cells]]) 

        p00 = permin_interp(p000, p001, w - n)
        p01 = permin_interp(p010, p011, w - n)
        p10 = permin_interp(p100, p101, w - n)
        p11 = permin_interp(p110, p111, w - n)

        p0 = permin_interp(p00, p01, v - b)
        p1 = permin_interp(p10, p11, v - b)

        p = permin_interp(p0, p1, u - l)
        
        buffer[i, j, k] = p


def cal_perlin_3d(buffer, cells=8):
    perlin_permute_3d_np = np.zeros((128, 128, 128), dtype=int)
    perlin_permute_3d_np[:cells, :cells, :cells] = np.random.permutation(cells*cells*cells).reshape(cells, cells, cells) % 12
    perlin_permute_3d.from_numpy(perlin_permute_3d_np)

    cal_perlin_3d_ti(buffer, cells)

    return buffer.to_numpy() 


def cal_perlin_3d_fbm(buffer=perlin_noise_3d, cells=8, layers=4):
    perlin_noise_3d_np = None
    for i in range(1, layers+1):        
        if i == 1:
            perlin_noise_3d_np = (0.5 + 0.5**layers) * cal_perlin_3d(buffer, cells)
        else:
            perlin_noise_3d_np += 0.5**i * cal_perlin_3d(buffer, cells)
        cells *= 2
    return perlin_noise_3d_np


# Worley 2D
worley_noise_2d = ti.field(ti.f64, shape=(512, 512))

worley_centers_2d = vec2f.field(shape=(512, 512))

@ti.kernel
def cal_worley_2d_ti(buffer: ti.template(), cells: ti.int32):
    cell_size = buffer.shape[0] // cells
    for i, j in buffer:
        u = (i + 0.5) / cell_size
        v = (j + 0.5) / cell_size

        l = int(ti.floor(u))
        b = int(ti.floor(v))

        p = 1.0

        for x, y in ti.static(ti.ndrange((-2, 3), (-2, 3))):
            r = vec2f(l + x, b + y) + worley_centers_2d[(l+x)%cells, (b+y)%cells] - vec2f(u, v)
            p = min(p, r.dot(r))

        buffer[i, j] = p


def cal_worley_2d(buffer, cells=8):
    worley_centers_2d_np = np.zeros((512, 512, 2), dtype=float)
    worley_centers_2d_np[:cells, :cells] = np.random.rand(cells*cells*2).reshape(cells, cells, 2)
    worley_centers_2d.from_numpy(worley_centers_2d_np)

    cal_worley_2d_ti(buffer, cells)

    return buffer.to_numpy() 


def cal_worley_2d_fbm(buffer=worley_noise_2d, cells=8, layers=4):
    worley_noise_2d_np = None
    for i in range(1, layers+1):        
        if i == 1:
            worley_noise_2d_np = (0.5 + 0.5**layers) * cal_worley_2d(buffer, cells)
        else:
            worley_noise_2d_np += 0.5**i * cal_worley_2d(buffer, cells)
        cells *= 2
    return worley_noise_2d_np


# Worley 3D
worley_noise_3d = ti.field(ti.f64, shape=(128, 128, 128))
worley_noise_3d_small = ti.field(ti.f64, shape=(32, 32, 32))

worley_centers_3d = vec3f.field(shape=(128, 128, 128))

@ti.kernel
def cal_worley_3d_ti(buffer: ti.template(), cells: ti.int32):
    cell_size = buffer.shape[0] // cells
    for i, j, k in buffer:
        u = (i + 0.5) / cell_size
        v = (j + 0.5) / cell_size
        w = (k + 0.5) / cell_size

        l = int(ti.floor(u))
        b = int(ti.floor(v))
        n = int(ti.floor(w))

        p = 1.0

        for x, y, z in ti.static(ti.ndrange((-2, 3), (-2, 3), (-2, 3))):
            r = vec3f(l + x, b + y, n + z) + worley_centers_3d[(l+x)%cells, (b+y)%cells, (n+z)%cells] - vec3f(u, v, w)
            p = min(p, r.dot(r))

        buffer[i, j, k] = p


def cal_worley_3d(buffer, cells=8):
    worley_centers_3d_np = np.zeros((128, 128, 128, 3), dtype=float)
    worley_centers_3d_np[:cells, :cells, :cells] = np.random.rand(cells*cells*cells*3).reshape(cells, cells, cells, 3)
    worley_centers_3d.from_numpy(worley_centers_3d_np)

    cal_worley_3d_ti(buffer, cells)

    return buffer.to_numpy() 


def cal_worley_3d_fbm(buffer=worley_noise_3d, cells=8, layers=4):
    worley_noise_3d_np = None
    for i in range(1, layers+1):        
        if i == 1:
            worley_noise_3d_np = (0.5 + 0.5**layers) * cal_worley_3d(buffer, cells)
        else:
            worley_noise_3d_np += 0.5**i * cal_worley_3d(buffer, cells)
        cells *= 2
    return worley_noise_3d_np


###########################

perlin_noise_3d_np = cal_perlin_3d_fbm()
perlin_noise_3d_np = (perlin_noise_3d_np - perlin_noise_3d_np.min()) / (perlin_noise_3d_np.max() - perlin_noise_3d_np.min())

worley_noise_3d_np = cal_worley_3d_fbm()
worley_noise_3d_np = (worley_noise_3d_np - worley_noise_3d_np.min()) / (worley_noise_3d_np.max() - worley_noise_3d_np.min())

noise_3d_np_small = cal_worley_3d_fbm(worley_noise_3d_small, 4, 3)
noise_3d_np_small = 1 - (noise_3d_np_small - noise_3d_np_small.min()) / (noise_3d_np_small.max() - noise_3d_np_small.min())

noise_3d_np = remap(perlin_noise_3d_np, worley_noise_3d_np - 1, 1, 0, 1)
noise_3d_np = (noise_3d_np - noise_3d_np.min()) / (noise_3d_np.max() - noise_3d_np.min())


perlin_noise_2d_np = cal_perlin_2d_fbm(cells=32, layers=4)
perlin_noise_2d_np = (perlin_noise_2d_np - perlin_noise_2d_np.min()) / (perlin_noise_2d_np.max() - perlin_noise_2d_np.min())
perlin_noise_2d_np *= 0.25

worley_noise_2d_np = cal_worley_2d_fbm(cells=32, layers=4)
worley_noise_2d_np = (worley_noise_2d_np - worley_noise_2d_np.min()) / (worley_noise_2d_np.max() - worley_noise_2d_np.min())

noise_2d_np_1 = remap(perlin_noise_2d_np, worley_noise_2d_np - 1, 1, 0, 1)
noise_2d_np_1 = (noise_2d_np_1 - noise_2d_np_1.min()) / (noise_2d_np_1.max() - noise_2d_np_1.min())
noise_2d_np_1 = remap(noise_2d_np_1, 0.7, 1, 0, 1)


perlin_noise_2d_np = cal_perlin_2d_fbm(cells=4, layers=7)
perlin_noise_2d_np = (perlin_noise_2d_np - perlin_noise_2d_np.min()) / (perlin_noise_2d_np.max() - perlin_noise_2d_np.min())
perlin_noise_2d_np *= 0.5

worley_noise_2d_np = cal_worley_2d_fbm(layers = 7)
worley_noise_2d_np = (worley_noise_2d_np - worley_noise_2d_np.min()) / (worley_noise_2d_np.max() - worley_noise_2d_np.min())

noise_2d_np_2 = remap(perlin_noise_2d_np, worley_noise_2d_np - 1, 1, 0, 1)
noise_2d_np_2 = (noise_2d_np_2 - noise_2d_np_2.min()) / (noise_2d_np_2.max() - noise_2d_np_2.min())

noise_2d_np = np.stack([noise_2d_np_1, noise_2d_np_2], axis=-1)


if __name__ == '__main__':
    noise_display = np.zeros((1024, 1024))
    noise_display[:512, :512] = noise_2d_np[:,:,0]
    noise_display[:512, 512:] = noise_2d_np[:,:,0]
    noise_display[512:, :512] = noise_2d_np[:,:,0]
    noise_display[512:, 512:] = noise_2d_np[:,:,0]
    gui = ti.GUI('Clouds', (1024, 1024))
    while gui.running:
        gui.get_event()
        mouse = gui.get_cursor_pos()
        if gui.is_pressed(ti.GUI.LMB):
            pass
        mouse_last = mouse
        gui.set_image(noise_display)
        gui.show()
