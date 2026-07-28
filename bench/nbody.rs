// benchmark-contract: nbody-symplectic-euler;bodies=5;steps=500000;dt=0.01;solar_mass=4*pi*pi;days_per_year=365.24;output=bits(energy)&(2^63-1)
//
// nbody — 500k symplectic-Euler steps of the Sun + four gas giants, then
// print the total energy (see the C peer for the full rationale).
//
// Rust never contracts a multiply-add into an fma without an explicit
// `f64::mul_add`, and `-C opt-level=2` implies no fast-math, so this
// port needs no flag to stay bit-identical with the other four.
const NBODY: usize = 5;
const STEPS: u32 = 500_000;
const DT: f64 = 0.01;

const PI: f64 = 3.141592653589793;
const SOLAR_MASS: f64 = 4.0 * PI * PI;
const DAYS_PER_YEAR: f64 = 365.24;

// Struct-of-arrays, matching all four peers — see the C peer for why the
// layout is pinned across the five ports rather than left to each
// language's idiom. Seven `[f64; 5]` fields in one struct is the same
// memory layout as seven free arrays, and stays safe Rust.
struct System {
    x: [f64; NBODY],
    y: [f64; NBODY],
    z: [f64; NBODY],
    vx: [f64; NBODY],
    vy: [f64; NBODY],
    vz: [f64; NBODY],
    mass: [f64; NBODY],
}

fn system() -> System {
    System {
        x: [
            0.0,
            4.84143144246472090e+00,
            8.34336671824457987e+00,
            1.28943695621391310e+01,
            1.53796971148509165e+01,
        ],
        y: [
            0.0,
            -1.16032004402742839e+00,
            4.12479856412430479e+00,
            -1.51111514016986312e+01,
            -2.59193146099879641e+01,
        ],
        z: [
            0.0,
            -1.03622044471123109e-01,
            -4.03523417114321381e-01,
            -2.23307578892655734e-01,
            1.79258772950371181e-01,
        ],
        vx: [
            0.0,
            1.66007664274403694e-03 * DAYS_PER_YEAR,
            -2.76742510726862411e-03 * DAYS_PER_YEAR,
            2.96460137564761618e-03 * DAYS_PER_YEAR,
            2.68067772490389322e-03 * DAYS_PER_YEAR,
        ],
        vy: [
            0.0,
            7.69901118419740425e-03 * DAYS_PER_YEAR,
            4.99852801234917238e-03 * DAYS_PER_YEAR,
            2.37847173959480950e-03 * DAYS_PER_YEAR,
            1.62824170038242295e-03 * DAYS_PER_YEAR,
        ],
        vz: [
            0.0,
            -6.90460016972063023e-05 * DAYS_PER_YEAR,
            2.30417297573763929e-05 * DAYS_PER_YEAR,
            -2.96589568540237556e-05 * DAYS_PER_YEAR,
            -9.51592254519715870e-05 * DAYS_PER_YEAR,
        ],
        mass: [
            SOLAR_MASS,
            9.54791938424326609e-04 * SOLAR_MASS,
            2.85885980666130812e-04 * SOLAR_MASS,
            4.36624404335156298e-05 * SOLAR_MASS,
            5.15138902046611451e-05 * SOLAR_MASS,
        ],
    }
}

// Put the system in the barycentric frame: without this the Sun drifts
// and the energy is not the conserved quantity the checksum assumes.
fn offset_momentum(b: &mut System) {
    let mut px = 0.0f64;
    let mut py = 0.0f64;
    let mut pz = 0.0f64;
    for i in 0..NBODY {
        px += b.vx[i] * b.mass[i];
        py += b.vy[i] * b.mass[i];
        pz += b.vz[i] * b.mass[i];
    }
    b.vx[0] = -px / SOLAR_MASS;
    b.vy[0] = -py / SOLAR_MASS;
    b.vz[0] = -pz / SOLAR_MASS;
}

fn advance(b: &mut System, dt: f64) {
    for i in 0..NBODY {
        for j in (i + 1)..NBODY {
            let dx = b.x[i] - b.x[j];
            let dy = b.y[i] - b.y[j];
            let dz = b.z[i] - b.z[j];
            let d2 = dx * dx + dy * dy + dz * dz;
            let mag = dt / (d2 * d2.sqrt());
            let mi = b.mass[i] * mag;
            let mj = b.mass[j] * mag;
            b.vx[i] -= dx * mj;
            b.vy[i] -= dy * mj;
            b.vz[i] -= dz * mj;
            b.vx[j] += dx * mi;
            b.vy[j] += dy * mi;
            b.vz[j] += dz * mi;
        }
    }
    for i in 0..NBODY {
        b.x[i] += dt * b.vx[i];
        b.y[i] += dt * b.vy[i];
        b.z[i] += dt * b.vz[i];
    }
}

fn energy(b: &System) -> f64 {
    let mut e = 0.0f64;
    for i in 0..NBODY {
        e += 0.5 * b.mass[i] * (b.vx[i] * b.vx[i] + b.vy[i] * b.vy[i] + b.vz[i] * b.vz[i]);
        for j in (i + 1)..NBODY {
            let dx = b.x[i] - b.x[j];
            let dy = b.y[i] - b.y[j];
            let dz = b.z[i] - b.z[j];
            e -= (b.mass[i] * b.mass[j]) / (dx * dx + dy * dy + dz * dz).sqrt();
        }
    }
    e
}

fn main() {
    let mut b = system();
    offset_momentum(&mut b);
    for _ in 0..STEPS {
        advance(&mut b, DT);
    }
    let e = energy(&b);
    println!("{}", e.to_bits() & 0x7fff_ffff_ffff_ffff);
}
