import imp
import numpy as np
from scipy import interpolate
import imageio
from tqdm import tqdm

tLUT_res = (256, 64)
msLUT_res = (32, 32)

# Units are in megameters.
ground_radius = 6.360
atmosphere_radius = 6.460

# These are per megameter.
rayleigh_scattering_base = np.array([5.802, 13.558, 33.1])
rayleigh_absorption_base = 0.0

mie_scattering_base = 3.996
mie_absorption_base = 4.4

ozone_absorption_base = np.array([0.650, 1.881, 0.085])


def rayIntersectSphere(ro, rd, rad):
    b = np.dot(ro, rd)
    c = np.dot(ro, ro) - rad * rad
    if c == 0: return 0.0
    if c > 0 and b > 0: return -1.0
    discr = b*b - c
    if discr < 0: return -1.0
    if discr > b * b: return (-b + np.sqrt(discr))
    return -b - np.sqrt(discr)


def getSphericalDir(theta, phi):
    cos_phi = np.cos(phi)
    sin_phi = np.sin(phi)
    cos_theta = np.cos(theta)
    sin_theta = np.sin(theta)
    return np.array([sin_phi * sin_theta, cos_phi, sin_phi * cos_theta])


def getMiePhase(cos_theta):
    g = 0.8
    scale = 3.0 / (8.0 * np.pi)

    num = (1.0 - g * g) * (1.0 + cos_theta * cos_theta)
    denom = (2.0 + g * g) * np.power((1.0 + g * g - 2.0 * g * cos_theta), 1.5)

    return scale * num / denom


def getRayleighPhase(cos_theta):
    k = 3.0 / (16.0 * np.pi)
    return k * (1.0 + cos_theta * cos_theta)


def getScatteringValues(pos):
    altitude_KM = max((np.linalg.norm(pos) - ground_radius)*1000.0, -100.0)
    # Note: Paper gets these switched up.
    rayleigh_density = np.exp(-altitude_KM/8.0)
    mie_density = np.exp(-altitude_KM/1.2)
    
    rayleigh_scattering = rayleigh_scattering_base * rayleigh_density
    rayleigh_absorption = rayleigh_absorption_base * rayleigh_density
    
    mie_scattering = mie_scattering_base * mie_density
    mie_absorption = mie_absorption_base * mie_density
    
    ozon_absorption = ozone_absorption_base * max(0.0, 1.0 - abs(altitude_KM - 25.0) / 15.0)
    
    extinction = rayleigh_scattering + rayleigh_absorption + mie_scattering + mie_absorption + ozon_absorption

    return rayleigh_scattering, mie_scattering, extinction


'''=============== Transmittance LUT ==============='''
tLUT = np.zeros((tLUT_res[1], tLUT_res[0], 3))
sun_transmittance_steps = 32

for i in tqdm(range(tLUT_res[1])):
    for j in tqdm(range(tLUT_res[0]), leave=bool(i == tLUT_res[1] - 1)):
        u = j / (tLUT_res[0] - 1)
        v = i / (tLUT_res[1] - 1)
        sun_cos_theta = 2 * u - 1
        sun_sin_theta = np.sqrt(1 - sun_cos_theta * sun_cos_theta)
        height = ground_radius + 1e-6 + v * (atmosphere_radius - ground_radius - 2e-6)
        pos = np.array([0, height, 0])
        sun_dir = np.array([0, sun_cos_theta, sun_sin_theta])

        if rayIntersectSphere(pos, sun_dir, ground_radius) > 0:
            transmittance = np.array([0., 0., 0.])
        else:
            atmo_dist = rayIntersectSphere(pos, sun_dir, atmosphere_radius)
            t = 0.
            transmittance = np.array([1., 1., 1.])
            for k in range(sun_transmittance_steps):
                new_t = (k + 0.3) / sun_transmittance_steps * atmo_dist
                dt = new_t - t
                t = new_t
                new_pos = pos + t * sun_dir

                rayleigh_scattering, mie_scattering, extinction = getScatteringValues(new_pos)

                transmittance *= np.exp(-dt * extinction)
        
        tLUT[i, j] = transmittance

imageio.imwrite('./utils/atmosphere_transmittance.png', (tLUT * 255).astype(np.uint8))

def getValFromTLUT(pos, sun_dir):
    height = np.linalg.norm(pos)
    up = pos / height
    sun_cos_theta = np.dot(sun_dir, up)
    u = 0.5 + 0.5 * sun_cos_theta
    v = (height - ground_radius) / (atmosphere_radius - ground_radius)
    if u < 0 or v < 0 : print(u, v)
    return interpolate.interpn(
        points=(np.linspace(0.5 / tLUT_res[1], 1 - 0.5 / tLUT_res[1], tLUT_res[1]), np.linspace(0, 1, tLUT_res[0])),
        values=tLUT,
        xi=np.array([v, u]),
        method='linear',
        bounds_error=False,
        fill_value=None
    )


'''=============== Multiple Scattering LUT ==============='''
msLUT = np.zeros((msLUT_res[1], msLUT_res[0], 3))
ms_steps = 20
sqrt_samples = 8

for i in tqdm(range(msLUT_res[1])):
    for j in tqdm(range(msLUT_res[0]), leave=bool(i == msLUT_res[1] - 1)):
        u = j / (msLUT_res[0] - 1)
        v = i / (msLUT_res[1] - 1)
        sun_cos_theta = 2 * u - 1
        sun_sin_theta = np.sqrt(1 - sun_cos_theta * sun_cos_theta)
        height = ground_radius + 1e-6 + v * (atmosphere_radius - ground_radius - 2e-6)
        pos = np.array([0, height, 0])
        sun_dir = np.array([0, sun_cos_theta, sun_sin_theta])

        # Calculates Equation (5) and (7) from the paper.
        lum_total = 0.0
        fms = 0.0
        inv_samples = 1.0 / (sqrt_samples * sqrt_samples)
        for l in range(sqrt_samples):
            for m in range(sqrt_samples):
                # This integral is symmetric about theta = 0 (or theta = PI), so we
                # only need to integrate from zero to PI, not zero to 2*PI.
                theta = np.pi * (l + 0.5) / sqrt_samples
                phi = np.arccos(1.0 - 2.0 * (m + 0.5) / sqrt_samples)
                ray_dir = getSphericalDir(theta, phi)
                
                atmo_dist = rayIntersectSphere(pos, ray_dir, atmosphere_radius)
                ground_dist = rayIntersectSphere(pos, ray_dir, ground_radius)
                t_max = atmo_dist if ground_dist <= 0 else ground_dist
                
                cos_theta = np.dot(ray_dir, sun_dir)
        
                mie_phase_value = getMiePhase(cos_theta)
                rayleigh_phase_value = getRayleighPhase(cos_theta)
                
                lum = 0.0
                lum_factor = 0.0
                transmittance = 1.0
                t = 0.0
                for step_i in range(ms_steps):
                    new_t = (step_i + 0.3) / ms_steps * t_max
                    dt = new_t - t
                    t = new_t
                    new_pos = pos + t * ray_dir

                    rayleigh_scattering, mie_scattering, extinction = getScatteringValues(new_pos)

                    sample_transmittance = np.exp(-dt * extinction)
                    
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
            
                fms += lum_factor * inv_samples
                lum_total += lum * inv_samples
        
        psi = lum_total / (1.0 - fms); 
        msLUT[i, j] = psi

imageio.imwrite('./utils/atmosphere_multiple_scattering.png', (msLUT * 255).astype(np.uint8))
