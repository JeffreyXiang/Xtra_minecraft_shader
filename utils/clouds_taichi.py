import taichi as ti
import numpy as np

ti.init(arch=ti.gpu, default_fp=ti.f64)  # Try to run on GPU

vec3f = ti.types.matrix(3, 1, ti.f64)
vec2f = ti.types.matrix(2, 1, ti.f64)

perlin_cells = None
perlin_cell_size = None

perlin_noise = ti.field(ti.f64, shape=(128, 128, 128))

perlin_grad = vec3f.field(shape=(12))
perlin_grad_np = np.array([
    [1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0],
    [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
    [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1]
], dtype=float)
perlin_grad.from_numpy(perlin_grad_np)

perlin_permute = ti.field(ti.i32, shape=(128+1, 128+1, 128+1))


@ti.func
def permin_interp(v1, v2, k):
    k = 6 * k**5 - 15 * k**4 + 10 * k**3
    return v1 * (1 - k) + v2 * k


@ti.kernel
def cal_perlin_ti(cell_size: ti.int32):
    for i, j, k in perlin_noise:
        u = (i + 0.5) / cell_size
        v = (j + 0.5) / cell_size
        w = (k + 0.5) / cell_size

        l = int(ti.floor(u))
        r = int(ti.ceil(u))
        b = int(ti.floor(v))
        t = int(ti.ceil(v))
        n = int(ti.floor(w))
        f = int(ti.ceil(w))

        p000 = ti.Vector([u - l, v - b, w - n]).dot(perlin_grad[perlin_permute[l, b, n]]) 
        p001 = ti.Vector([u - l, v - b, w - f]).dot(perlin_grad[perlin_permute[l, b, f]]) 
        p010 = ti.Vector([u - l, v - t, w - n]).dot(perlin_grad[perlin_permute[l, t, n]]) 
        p011 = ti.Vector([u - l, v - t, w - f]).dot(perlin_grad[perlin_permute[l, t, f]]) 
        p100 = ti.Vector([u - r, v - b, w - n]).dot(perlin_grad[perlin_permute[r, b, n]]) 
        p101 = ti.Vector([u - r, v - b, w - f]).dot(perlin_grad[perlin_permute[r, b, f]]) 
        p110 = ti.Vector([u - r, v - t, w - n]).dot(perlin_grad[perlin_permute[r, t, n]]) 
        p111 = ti.Vector([u - r, v - t, w - f]).dot(perlin_grad[perlin_permute[r, t, f]]) 

        p00 = permin_interp(p000, p001, w - n)
        p01 = permin_interp(p010, p011, w - n)
        p10 = permin_interp(p100, p101, w - n)
        p11 = permin_interp(p110, p111, w - n)

        p0 = permin_interp(p00, p01, v - b)
        p1 = permin_interp(p10, p11, v - b)

        p = permin_interp(p0, p1, u - l)
        
        perlin_noise[i, j, k] = p * 0.5 + 0.5


def cal_perlin(cells=8):
    global perlin_cells, perlin_cell_size, perlin_permute
    perlin_cells = cells
    perlin_cell_size = 128 // perlin_cells

    perlin_permute_np = np.zeros((128+1, 128+1, 128+1), dtype=int)
    perlin_permute_np[:perlin_cells, :perlin_cells, :perlin_cells] = np.random.permutation(perlin_cells*perlin_cells*perlin_cells).reshape(perlin_cells, perlin_cells, perlin_cells) % 12
    perlin_permute_np[perlin_cells, :perlin_cells+1, :perlin_cells+1] = perlin_permute_np[0, :perlin_cells+1, :perlin_cells+1]
    perlin_permute_np[:perlin_cells+1, perlin_cells, :perlin_cells+1] = perlin_permute_np[:perlin_cells+1, 0, :perlin_cells+1]
    perlin_permute_np[:perlin_cells+1, :perlin_cells+1, perlin_cells] = perlin_permute_np[:perlin_cells+1, :perlin_cells+1, 0]
    perlin_permute.from_numpy(perlin_permute_np)

    cal_perlin_ti(perlin_cell_size)

    return perlin_noise.to_numpy() 


def cal_perlin_fbm(cells=4, layers=6):
    perlin_noise_np = None
    for i in range(1, layers+1):        
        if i == 1:
            perlin_noise_np = (0.5 + 0.5**layers) * cal_perlin(cells)
        else:
            perlin_noise_np += 0.5**i * cal_perlin(cells)
        cells *= 2
    return perlin_noise_np


perlin_noise_np = cal_perlin_fbm()
perlin_noise_np = (perlin_noise_np - perlin_noise_np.min()) / (perlin_noise_np.max() - perlin_noise_np.min())

if __name__ == '__main__':
    gui = ti.GUI('Clouds', (128, 128))
    while gui.running:
        gui.get_event()
        mouse = gui.get_cursor_pos()
        if gui.is_pressed(ti.GUI.LMB):
            pass
        mouse_last = mouse
        gui.set_image(perlin_noise_np[:,:,0])
        gui.show()
