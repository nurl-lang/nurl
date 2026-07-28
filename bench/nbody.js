// benchmark-contract: nbody-symplectic-euler;bodies=5;steps=500000;dt=0.01;solar_mass=4*pi*pi;days_per_year=365.24;output=bits(energy)&(2^63-1)
//
// nbody — 500k symplectic-Euler steps of the Sun + four gas giants, then
// print the total energy (see the C peer for the full rationale).
//
// This is the one row in the suite where JavaScript is not handicapped.
// The other 64-bit rows force this port onto BigInt because JS has no
// integer type; here JS's single numeric type *is* the IEEE-754 double
// the benchmark is defined in, and `Math.sqrt` is the same correctly
// rounded hardware sqrt the compiled backends call. So Node runs
// precisely the same arithmetic they do, with no representation tax —
// what is left in the cell is JIT quality.
//
// BigInt appears exactly once, after the timed work is over, to read the
// result's bit pattern out of the Float64Array for the checksum.
const NBODY = 5;
const STEPS = 500000;
const DT = 0.01;

const PI = 3.141592653589793;
const SOLAR_MASS = 4.0 * PI * PI;
const DAYS_PER_YEAR = 365.24;

const x = Float64Array.from([
    0.0, 4.84143144246472090e+00, 8.34336671824457987e+00,
    1.28943695621391310e+01, 1.53796971148509165e+01]);
const y = Float64Array.from([
    0.0, -1.16032004402742839e+00, 4.12479856412430479e+00,
    -1.51111514016986312e+01, -2.59193146099879641e+01]);
const z = Float64Array.from([
    0.0, -1.03622044471123109e-01, -4.03523417114321381e-01,
    -2.23307578892655734e-01, 1.79258772950371181e-01]);
const vx = Float64Array.from([
    0.0, 1.66007664274403694e-03 * DAYS_PER_YEAR,
    -2.76742510726862411e-03 * DAYS_PER_YEAR,
    2.96460137564761618e-03 * DAYS_PER_YEAR,
    2.68067772490389322e-03 * DAYS_PER_YEAR]);
const vy = Float64Array.from([
    0.0, 7.69901118419740425e-03 * DAYS_PER_YEAR,
    4.99852801234917238e-03 * DAYS_PER_YEAR,
    2.37847173959480950e-03 * DAYS_PER_YEAR,
    1.62824170038242295e-03 * DAYS_PER_YEAR]);
const vz = Float64Array.from([
    0.0, -6.90460016972063023e-05 * DAYS_PER_YEAR,
    2.30417297573763929e-05 * DAYS_PER_YEAR,
    -2.96589568540237556e-05 * DAYS_PER_YEAR,
    -9.51592254519715870e-05 * DAYS_PER_YEAR]);
const mass = Float64Array.from([
    SOLAR_MASS, 9.54791938424326609e-04 * SOLAR_MASS,
    2.85885980666130812e-04 * SOLAR_MASS,
    4.36624404335156298e-05 * SOLAR_MASS,
    5.15138902046611451e-05 * SOLAR_MASS]);

// Put the system in the barycentric frame: without this the Sun drifts
// and the energy is not the conserved quantity the checksum assumes.
function offsetMomentum() {
    let px = 0.0, py = 0.0, pz = 0.0;
    for (let i = 0; i < NBODY; i++) {
        px += vx[i] * mass[i];
        py += vy[i] * mass[i];
        pz += vz[i] * mass[i];
    }
    vx[0] = -px / SOLAR_MASS;
    vy[0] = -py / SOLAR_MASS;
    vz[0] = -pz / SOLAR_MASS;
}

function advance(dt) {
    for (let i = 0; i < NBODY; i++) {
        for (let j = i + 1; j < NBODY; j++) {
            const dx = x[i] - x[j];
            const dy = y[i] - y[j];
            const dz = z[i] - z[j];
            const d2 = dx * dx + dy * dy + dz * dz;
            const mag = dt / (d2 * Math.sqrt(d2));
            const mi = mass[i] * mag;
            const mj = mass[j] * mag;
            vx[i] -= dx * mj;
            vy[i] -= dy * mj;
            vz[i] -= dz * mj;
            vx[j] += dx * mi;
            vy[j] += dy * mi;
            vz[j] += dz * mi;
        }
    }
    for (let i = 0; i < NBODY; i++) {
        x[i] += dt * vx[i];
        y[i] += dt * vy[i];
        z[i] += dt * vz[i];
    }
}

function energy() {
    let e = 0.0;
    for (let i = 0; i < NBODY; i++) {
        e += 0.5 * mass[i] * (vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i]);
        for (let j = i + 1; j < NBODY; j++) {
            const dx = x[i] - x[j];
            const dy = y[i] - y[j];
            const dz = z[i] - z[j];
            e -= (mass[i] * mass[j]) / Math.sqrt(dx * dx + dy * dy + dz * dz);
        }
    }
    return e;
}

offsetMomentum();
for (let s = 0; s < STEPS; s++) {
    advance(DT);
}
const e = energy();

const buf = new ArrayBuffer(8);
new Float64Array(buf)[0] = e;
const bits = new BigUint64Array(buf)[0];
console.log((bits & 0x7fffffffffffffffn).toString());
