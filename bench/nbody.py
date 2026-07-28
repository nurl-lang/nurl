#!/usr/bin/env python3
# benchmark-contract: nbody-symplectic-euler;bodies=5;steps=500000;dt=0.01;solar_mass=4*pi*pi;days_per_year=365.24;output=bits(energy)&(2^63-1)
#
# nbody — 500k symplectic-Euler steps of the Sun + four gas giants, then
# print the total energy (see the C peer for the full rationale).
#
# Python's float *is* the IEEE-754 double the other four use, and its +,
# -, *, / and math.sqrt are the correctly-rounded hardware operations, so
# this row costs Python none of the bignum masking the integer rows do.
# What it measures instead is pure interpreter overhead: the same
# arithmetic, one bytecode dispatch and one boxed float per operation.
#
# Flat lists rather than a Body class or tuples: attribute lookup would
# dominate the arithmetic and make the row a measurement of Python's
# object model instead of its float path.
from math import sqrt
import struct

NBODY = 5
STEPS = 500000
DT = 0.01

PI = 3.141592653589793
SOLAR_MASS = 4.0 * PI * PI
DAYS_PER_YEAR = 365.24

x = [0.0, 4.84143144246472090e+00, 8.34336671824457987e+00,
     1.28943695621391310e+01, 1.53796971148509165e+01]
y = [0.0, -1.16032004402742839e+00, 4.12479856412430479e+00,
     -1.51111514016986312e+01, -2.59193146099879641e+01]
z = [0.0, -1.03622044471123109e-01, -4.03523417114321381e-01,
     -2.23307578892655734e-01, 1.79258772950371181e-01]
vx = [0.0, 1.66007664274403694e-03 * DAYS_PER_YEAR,
      -2.76742510726862411e-03 * DAYS_PER_YEAR,
      2.96460137564761618e-03 * DAYS_PER_YEAR,
      2.68067772490389322e-03 * DAYS_PER_YEAR]
vy = [0.0, 7.69901118419740425e-03 * DAYS_PER_YEAR,
      4.99852801234917238e-03 * DAYS_PER_YEAR,
      2.37847173959480950e-03 * DAYS_PER_YEAR,
      1.62824170038242295e-03 * DAYS_PER_YEAR]
vz = [0.0, -6.90460016972063023e-05 * DAYS_PER_YEAR,
      2.30417297573763929e-05 * DAYS_PER_YEAR,
      -2.96589568540237556e-05 * DAYS_PER_YEAR,
      -9.51592254519715870e-05 * DAYS_PER_YEAR]
mass = [SOLAR_MASS, 9.54791938424326609e-04 * SOLAR_MASS,
        2.85885980666130812e-04 * SOLAR_MASS,
        4.36624404335156298e-05 * SOLAR_MASS,
        5.15138902046611451e-05 * SOLAR_MASS]


# Put the system in the barycentric frame: without this the Sun drifts
# and the energy is not the conserved quantity the checksum assumes.
def offset_momentum():
    px = 0.0
    py = 0.0
    pz = 0.0
    for i in range(NBODY):
        px += vx[i] * mass[i]
        py += vy[i] * mass[i]
        pz += vz[i] * mass[i]
    vx[0] = -px / SOLAR_MASS
    vy[0] = -py / SOLAR_MASS
    vz[0] = -pz / SOLAR_MASS


def advance(dt):
    for i in range(NBODY):
        for j in range(i + 1, NBODY):
            dx = x[i] - x[j]
            dy = y[i] - y[j]
            dz = z[i] - z[j]
            d2 = dx * dx + dy * dy + dz * dz
            mag = dt / (d2 * sqrt(d2))
            mi = mass[i] * mag
            mj = mass[j] * mag
            vx[i] -= dx * mj
            vy[i] -= dy * mj
            vz[i] -= dz * mj
            vx[j] += dx * mi
            vy[j] += dy * mi
            vz[j] += dz * mi
    for i in range(NBODY):
        x[i] += dt * vx[i]
        y[i] += dt * vy[i]
        z[i] += dt * vz[i]


def energy():
    e = 0.0
    for i in range(NBODY):
        e += 0.5 * mass[i] * (vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i])
        for j in range(i + 1, NBODY):
            dx = x[i] - x[j]
            dy = y[i] - y[j]
            dz = z[i] - z[j]
            e -= (mass[i] * mass[j]) / sqrt(dx * dx + dy * dy + dz * dz)
    return e


offset_momentum()
for _ in range(STEPS):
    advance(DT)
e = energy()

bits = struct.unpack('<Q', struct.pack('<d', e))[0]
print(bits & 0x7fffffffffffffff)
