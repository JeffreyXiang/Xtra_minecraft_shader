import numpy as np
import taichi as ti

ti.init(arch=ti.gpu, default_fp =ti.f64)  # Try to run on GPU

vec3f = ti.types.matrix(3, 1, ti.f64)
vec2f = ti.types.matrix(2, 1, ti.f64)

tLUT_res = (256, 64)
msLUT_res = (32, 32)
ms_samples = 4096

tLUT = vec3f.field(shape=(tLUT_res[0], tLUT_res[1]))
ms_buffer_lum = vec3f.field(shape=(msLUT_res[0], msLUT_res[1], ms_samples))
ms_buffer_fms = vec3f.field(shape=(msLUT_res[0], msLUT_res[1], ms_samples))
msLUT = vec3f.field(shape=(msLUT_res[0], msLUT_res[1]))

# Units are in megameters.
ground_radius = 6.360
atmosphere_radius = 6.460

# These are per megameter.
rayleigh_scattering_base = vec3f(5.802, 13.558, 33.1)
rayleigh_absorption_base = 0.0

mie_scattering_base = 3.996
mie_absorption_base = 4.4

ozone_absorption_base = vec3f(0.650, 1.881, 0.085)

ground_albedo = 0.3


@ti.func
def rayIntersectSphere(ro, rd, rad: ti.f64) -> ti.f64:
    res = 0.0
    b = ro.dot(rd)
    c = ro.dot(ro) - rad * rad
    if c > 0 and b > 0: res = -1.0
    else:
        discr = b * b - c
        if discr < 0: res = -1.0
        elif discr > b * b: res = (-b + ti.sqrt(discr))
        else: res = -b - ti.sqrt(discr)
    return res


@ti.func
def getSphericalDir(theta: ti.f64, cos_phi: ti.f64) -> vec3f:
    sin_phi = ti.sqrt(1 - cos_phi * cos_phi)
    cos_theta = ti.cos(theta)
    sin_theta = ti.sin(theta)
    return vec3f(sin_phi * sin_theta, cos_phi, sin_phi * cos_theta)


@ti.func
def getMiePhase(cos_theta: ti.f64):
    g = 0.8
    scale = 3.0 / (8.0 * np.pi)

    num = (1.0 - g * g) * (1.0 + cos_theta * cos_theta)
    denom = (2.0 + g * g) * ti.pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5)

    return scale * num / denom


@ti.func
def getRayleighPhase(cos_theta: ti.f64):
    k = 3.0 / (16.0 * np.pi)
    return k * (1.0 + cos_theta * cos_theta)


@ti.func
def getScatteringValues(pos):
    altitude_KM = ti.max((pos.norm() - ground_radius) * 1000.0, -100.0)
    # Note: Paper gets these switched up.
    rayleigh_density = ti.min(ti.exp(-altitude_KM/8.0), 10)
    mie_density = ti.min(ti.exp(-altitude_KM/1.2), 10)
    
    rayleigh_scattering = rayleigh_scattering_base * rayleigh_density
    rayleigh_absorption = rayleigh_absorption_base * rayleigh_density
    
    mie_scattering = mie_scattering_base * mie_density
    mie_absorption = mie_absorption_base * mie_density
    
    ozon_absorption = ozone_absorption_base * ti.max(0.0, 1.0 - ti.abs(altitude_KM - 25.0) / 15.0)
    
    extinction = rayleigh_scattering + rayleigh_absorption + mie_scattering + mie_absorption + ozon_absorption

    return rayleigh_scattering, mie_scattering, extinction


@ti.func
def bilerp(texture: ti.template(), u: ti.f64, v: ti.f64):
    u = u * texture.shape[0] - 0.5
    v = v * texture.shape[1] - 0.5
    l = ti.floor(u)
    r = ti.ceil(u)
    b = ti.floor(v)
    t = ti.ceil(v)
    w00 = (r - u) * (t - v)
    w01 = (r - u) * (v - b)
    w10 = (u - l) * (t - v)
    w11 = (u - l) * (v - b)
    l_ = ti.cast(ti.max(0, ti.min(texture.shape[0] - 1, l)), ti.int32)
    r_ = ti.cast(ti.max(0, ti.min(texture.shape[0] - 1, r)), ti.int32)
    b_ = ti.cast(ti.max(0, ti.min(texture.shape[1] - 1, b)), ti.int32)
    t_ = ti.cast(ti.max(0, ti.min(texture.shape[1] - 1, t)), ti.int32)
    res = w00 * texture[l_, b_] + w01 * texture[l_, t_] + w10 * texture[r_, b_] + w11 * texture[r_, t_]
    return res


@ti.func
def getValFromTLUT(pos, sun_dir):
    height = pos.norm()
    up = pos / height
    sun_cos_theta = sun_dir.dot(up)
    u = 0.5 + 0.5 * sun_cos_theta
    v = (height - ground_radius) / (atmosphere_radius - ground_radius)
    return bilerp(tLUT, u, v)


@ti.func
def getValFromMsLUT(pos, sun_dir):
    height = pos.norm()
    up = pos / height
    sun_cos_theta = sun_dir.dot(up)
    u = 0.5 + 0.5 * sun_cos_theta
    v = (height - ground_radius) / (atmosphere_radius - ground_radius)
    return bilerp(msLUT, u, v)


'''=============== Transmittance LUT ==============='''
sun_transmittance_steps = 1024

@ti.kernel
def cal_tLUT():
    for i, j in tLUT:
        u = i / (tLUT_res[0] - 1)
        v = j / (tLUT_res[1] - 1)
        sun_cos_theta = 2 * u - 1
        sun_sin_theta = ti.sqrt(1 - sun_cos_theta * sun_cos_theta)
        height = ground_radius + 1e-6 + v * (atmosphere_radius - ground_radius - 2e-6)
        pos = vec3f(0, height, 0)
        sun_dir = vec3f(0, sun_cos_theta, sun_sin_theta)
        transmittance = vec3f(0.0)
        atmo_dist = rayIntersectSphere(pos, sun_dir, atmosphere_radius)
        t = 0.
        transmittance = vec3f(1., 1., 1.)
        for k in range(sun_transmittance_steps):
            new_t = (float(k) + 0.3) / sun_transmittance_steps * atmo_dist
            dt = new_t - t
            t = new_t
            new_pos = pos + t * sun_dir
            rayleigh_scattering, mie_scattering, extinction = getScatteringValues(new_pos)
            transmittance *= ti.exp(-dt * extinction)
        tLUT[i, j] = transmittance


'''=============== Multiple Scattering LUT ==============='''
ms_steps = 128

@ti.kernel
def cal_ms_buffer():
    for i, j, l in ms_buffer_lum:
        u = i / (msLUT_res[0] - 1)
        v = j / (msLUT_res[1] - 1)
        sun_cos_theta = 2 * u - 1
        sun_sin_theta = ti.sqrt(1 - sun_cos_theta * sun_cos_theta)
        height = ground_radius + 1e-6 + v * (atmosphere_radius - ground_radius - 2e-6)
        pos = vec3f(0, height, 0)
        sun_dir = vec3f(0, sun_cos_theta, sun_sin_theta)

        # Calculates Equation (5) and (7) from the paper.
        # This integral is symmetric about theta = 0 (or theta = PI), so we
        # only need to integrate from zero to PI, not zero to 2*PI.
        
        theta = l * (ti.sqrt(5) - 1) / 2
        theta = theta - ti.floor(theta)
        theta = theta * np.pi
        cos_phi = l / (ms_samples - 1)
        cos_phi = 2 * cos_phi - 1
        ray_dir = getSphericalDir(theta, cos_phi)
        
        atmo_dist = rayIntersectSphere(pos, ray_dir, atmosphere_radius)
        ground_dist = rayIntersectSphere(pos, ray_dir, ground_radius)
        t_max = atmo_dist if ground_dist <= 0 else ti.min(ground_dist + 1, atmo_dist)
        
        cos_theta = ray_dir.dot(sun_dir)

        mie_phase_value = getMiePhase(cos_theta)
        rayleigh_phase_value = getRayleighPhase(cos_theta)
        
        lum = vec3f(0.0)
        lum_factor = vec3f(0.0)
        transmittance = vec3f(1.0)
        t = 0.0
        for step_i in range(ms_steps):
            new_t = (step_i + 0.3) / ms_steps * t_max
            dt = new_t - t
            t = new_t
            new_pos = pos + t * ray_dir

            rayleigh_scattering, mie_scattering, extinction = getScatteringValues(new_pos)

            sample_transmittance = ti.exp(-dt * extinction)
            
            # Integrate within each segment.
            scattering_no_phase = rayleigh_scattering + mie_scattering
            scattering_f = (scattering_no_phase - scattering_no_phase * sample_transmittance) / extinction
            lum_factor += transmittance * scattering_f
            
            # This is slightly different from the paper, but I think the paper has a mistake?
            # In equation (6), I think S(x,w_s) should be S(x-tv,w_s).
            sun_transmittance = getValFromTLUT(new_pos, sun_dir)

            rayleigh_in_scattering = rayleigh_scattering * rayleigh_phase_value
            mie_in_scattering = mie_scattering * mie_phase_value
            in_scattering = (rayleigh_in_scattering + mie_in_scattering) * sun_transmittance

            # Integrated scattering within path segment.
            scattering = (in_scattering - in_scattering * sample_transmittance) / extinction

            lum += transmittance * scattering
            transmittance *= sample_transmittance
        if ground_dist > 0.0:
            hit_pos = pos + ground_dist * ray_dir
            hit_pos = hit_pos.normalized() * ground_radius
            lum += transmittance * ground_albedo * getValFromTLUT(hit_pos, sun_dir)

    
        ms_buffer_fms[i, j, l] = lum_factor
        ms_buffer_lum[i, j, l] = lum


@ti.kernel
def sum_ms_buffer():
    for i, j in msLUT:
        lum = vec3f(0.0)
        fms = vec3f(0.0)
        inv_samples = 1.0 / ms_samples
        for l in range(ms_samples):
            fms += ms_buffer_fms[i, j, l] * inv_samples
            lum += ms_buffer_lum[i, j, l] * inv_samples
        psi = lum / (1.0 - fms) 
        msLUT[i, j] = psi
        

def cal_msLUT():
    cal_ms_buffer()
    sum_ms_buffer()


'''=============== Sky View ==============='''
sky_view_steps = 32
skyLUT_res = (256, 256)
skyLUT = vec3f.field(shape=(skyLUT_res[0], skyLUT_res[1]))

view_pos = vec3f(0.0, ground_radius + 0.0002, 0.0)
sun_angle = 1.

@ti.kernel
def cal_skyLUT(sun_angle: ti.f64):
    for i, j in skyLUT:
        u = i / (skyLUT_res[0] - 1)
        v = j / (skyLUT_res[1] - 1)
        azimuth_angle = (u - 0.5) * 2.0 * np.pi
        # Non-linear mapping of altitude. See Section 5.3 of the paper.
        adjV = 0.0
        if (v < 0.5):
            coord = 1.0 - 2.0 * v
            adjV = -coord * coord
        else:
            coord = v * 2.0 - 1.0
            adjV = coord * coord
        
        height = view_pos.norm()
        up = view_pos / height
        horizon_angle = ti.acos(ti.sqrt(height * height - ground_radius * ground_radius) / height) - 0.5 * np.pi
        altitude_angle = adjV * 0.5 * np.pi + horizon_angle
        
        cos_altitude = ti.cos(altitude_angle)
        ray_dir = vec3f(cos_altitude * ti.sin(azimuth_angle), ti.sin(altitude_angle), -cos_altitude * ti.cos(azimuth_angle))
        
        sun_altitude = sun_angle
        sun_dir = vec3f(0.0, ti.sin(sun_altitude), -ti.cos(sun_altitude))
        
        atmo_dist = rayIntersectSphere(view_pos, ray_dir, atmosphere_radius)
        ground_dist = rayIntersectSphere(view_pos, ray_dir, ground_radius)
        t_max = atmo_dist if ground_dist < 0.0 else ground_dist
        cos_theta = ray_dir.dot(sun_dir)
    
        mie_phase_value = getMiePhase(cos_theta)
        rayleigh_phase_value = getRayleighPhase(cos_theta)
        
        lum = vec3f(0.0)
        transmittance = vec3f(1.0)
        t = 0.0
        for step_i in range(sky_view_steps):
            new_t = ((step_i + 0.3)/sky_view_steps) * t_max
            dt = new_t - t
            t = new_t
            
            new_pos = view_pos + t * ray_dir
            
            rayleigh_scattering, mie_scattering, extinction = getScatteringValues(new_pos)
            
            sample_transmittance = ti.exp(-dt * extinction)

            sun_transmittance = getValFromTLUT(new_pos, sun_dir)
            psiMS = getValFromMsLUT(new_pos, sun_dir)
            
            rayleigh_in_scattering = rayleigh_scattering * (rayleigh_phase_value * sun_transmittance + psiMS)
            mie_in_scattering = mie_scattering * (mie_phase_value * sun_transmittance + psiMS)
            in_scattering = (rayleigh_in_scattering + mie_in_scattering)

            # Integrated scattering within path segment.
            scattering_integral = (in_scattering - in_scattering * sample_transmittance) / extinction
            lum += scattering_integral * transmittance
            transmittance *= sample_transmittance

        skyLUT[i, j] = lum


cal_tLUT()
cal_msLUT()


tLUT_np = tLUT.to_numpy()
msLUT_np = msLUT.to_numpy()
slLUT_np = np.zeros((224, 1, 3))
for idx, sun_height in enumerate(np.linspace(-1, 1, 224)):
    cal_skyLUT(np.arcsin(sun_height))
    slLUT_np[idx] = skyLUT.to_numpy()[:, 128:].mean(axis=0).mean(axis=0)

ti.tools.imwrite(tLUT_np, './utils/atmosphere_transmittance.png')
ti.tools.imwrite(msLUT_np * 5, './utils/atmosphere_multiple_scattering.png')
ti.tools.imwrite(slLUT_np * 5, './utils/atmosphere_sky_light.png')

tLUT_np = tLUT_np.transpose(1, 0, 2)
msLUT_np = msLUT_np.transpose(1, 0, 2)
slLUT_np = slLUT_np.transpose(1, 0, 2)

if __name__ == '__main__':
    gui = ti.GUI('Atmosphere', (256, 256))
    while gui.running:
        gui.get_event()
        mouse = gui.get_cursor_pos()
        if gui.is_pressed(ti.GUI.LMB):
            sun_angle += mouse[1] - mouse_last[1]
        mouse_last = mouse
        cal_skyLUT(sun_angle)
        gui.set_image(skyLUT)
        gui.show()
