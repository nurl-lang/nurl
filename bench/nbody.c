// benchmark-contract: nbody-symplectic-euler;bodies=5;steps=500000;dt=0.01;solar_mass=4*pi*pi;days_per_year=365.24;output=bits(energy)&(2^63-1)
//
// nbody — 500k symplectic-Euler steps of the Sun + four gas giants, then
// print the total energy of the system. Ten body pairs per step, each
// costing one sqrt and one divide: this is the only row in the suite
// whose critical path runs through the FPU's long-latency, non-pipelined
// units rather than the integer ALU.
//
// It is also the only row where JavaScript is not handicapped. Every
// other 64-bit row forces Node onto BigInt because JS has no integer
// type; here JS's one numeric type *is* the IEEE double this benchmark
// is written in, so Node runs the same arithmetic the compiled backends
// do. A suite in which Node loses every row by 50x invites the suspicion
// that the corpus was picked to make it lose.
//
// Bit-exactness across five languages rests on three things:
//
//   * No `-ffast-math` anywhere. Without it LLVM may not reassociate or
//     vectorise an FP reduction, so the sum stays in source order.
//   * No multiply-add contraction. clang defaults to
//     `-ffp-contract=on` at -O2, and fusing `dx*dx + dy*dy` into an fma
//     is *more* accurate than the unfused form — which is exactly the
//     problem, since JS and Python cannot fuse and would disagree in
//     the last bits. It is moot as the suite is currently built: the
//     baseline `x86-64` target has no FMA instruction to contract into,
//     and `bench.sh` sets no `-march`. **If a `-march=` or
//     `-mfma`-bearing flag is ever added to `bench.sh`, this row needs
//     an explicit `-ffp-contract=off` or its gate will start failing.**
//     Rust never contracts without `f64::mul_add`, so it is unaffected.
//     Lacking FMA hardware is NOT full protection, either: clang still
//     emits `llvm.fmuladd`, and LLVM constant-folds that *fused* — a
//     variant of this file with the whole setup visible to the constant
//     folder produced a different checksum at plain `-O2`, no `-march`
//     involved. The gate catches it; this note explains what happened.
//   * The five files evaluate the operations in the same order. IEEE
//     addition is not associative, so a reordered sum is a different
//     number, and the gate would catch it as a mismatch rather than
//     letting it through as a fast cell.
//
// Everything else is IEEE-754 exact by specification: +, -, *, / and
// sqrt are all correctly rounded, so five conforming implementations
// evaluating the same expressions in the same order must agree to the
// bit. That is what this row's checksum asserts.
//
// Contract: the process prints exactly one line — the bit pattern of
// the final energy as a double, masked to 63 bits so the languages
// without an unsigned 64-bit type can print it too.
#include <math.h>
#include <stdio.h>
#include <string.h>

#define NBODY 5
#define STEPS 500000
#define DT 0.01

#define PI 3.141592653589793
#define SOLAR_MASS (4.0 * PI * PI)
#define DAYS_PER_YEAR 365.24

// Struct-of-arrays, matching all four peers. An array of `struct body`
// is the more idiomatic C and is about 6% faster here — one base
// pointer per body instead of seven — but the layout has to be the same
// in all five ports or the row measures struct layout as well as FP
// throughput. Measured on this corpus: AoS C retires 274.0M
// instructions, SoA C 290.1M. (NURL and Rust retire ~185M on the same
// source shape: their frontends' IR passes LLVM's full-unroll cost
// model at the O3 backend stage, which flattens the five-body loops and
// keeps the state in registers; clang's C-shaped IR does not, at any
// flag level tried — -O3, -fno-math-errno, locals, LTO. The gap is an
// LLVM cost-model artifact, not extra work in the C.) Held to two
// layouts, the row would have added a 6% spread that has nothing to do
// with floating point. SoA is the one layout that is natural in all five
// languages at once: an AoS Python port would be a list of objects and
// would measure the interpreter's object model instead of its float
// path.
static double x[NBODY] = {0.0, 4.84143144246472090e+00,
                          8.34336671824457987e+00, 1.28943695621391310e+01,
                          1.53796971148509165e+01};
static double y[NBODY] = {0.0, -1.16032004402742839e+00,
                          4.12479856412430479e+00, -1.51111514016986312e+01,
                          -2.59193146099879641e+01};
static double z[NBODY] = {0.0, -1.03622044471123109e-01,
                          -4.03523417114321381e-01, -2.23307578892655734e-01,
                          1.79258772950371181e-01};
static double vx[NBODY] = {0.0, 1.66007664274403694e-03 * DAYS_PER_YEAR,
                           -2.76742510726862411e-03 * DAYS_PER_YEAR,
                           2.96460137564761618e-03 * DAYS_PER_YEAR,
                           2.68067772490389322e-03 * DAYS_PER_YEAR};
static double vy[NBODY] = {0.0, 7.69901118419740425e-03 * DAYS_PER_YEAR,
                           4.99852801234917238e-03 * DAYS_PER_YEAR,
                           2.37847173959480950e-03 * DAYS_PER_YEAR,
                           1.62824170038242295e-03 * DAYS_PER_YEAR};
static double vz[NBODY] = {0.0, -6.90460016972063023e-05 * DAYS_PER_YEAR,
                           2.30417297573763929e-05 * DAYS_PER_YEAR,
                           -2.96589568540237556e-05 * DAYS_PER_YEAR,
                           -9.51592254519715870e-05 * DAYS_PER_YEAR};
static double mass[NBODY] = {SOLAR_MASS,
                             9.54791938424326609e-04 * SOLAR_MASS,
                             2.85885980666130812e-04 * SOLAR_MASS,
                             4.36624404335156298e-05 * SOLAR_MASS,
                             5.15138902046611451e-05 * SOLAR_MASS};

// Put the system in the barycentric frame: without this the Sun drifts
// and the energy is not the conserved quantity the checksum assumes.
static void offset_momentum(void) {
  double px = 0.0, py = 0.0, pz = 0.0;
  for (int i = 0; i < NBODY; ++i) {
    px += vx[i] * mass[i];
    py += vy[i] * mass[i];
    pz += vz[i] * mass[i];
  }
  vx[0] = -px / SOLAR_MASS;
  vy[0] = -py / SOLAR_MASS;
  vz[0] = -pz / SOLAR_MASS;
}

static void advance(double dt) {
  for (int i = 0; i < NBODY; ++i) {
    for (int j = i + 1; j < NBODY; ++j) {
      double dx = x[i] - x[j];
      double dy = y[i] - y[j];
      double dz = z[i] - z[j];
      double d2 = dx * dx + dy * dy + dz * dz;
      double mag = dt / (d2 * sqrt(d2));
      double mi = mass[i] * mag;
      double mj = mass[j] * mag;
      vx[i] -= dx * mj;
      vy[i] -= dy * mj;
      vz[i] -= dz * mj;
      vx[j] += dx * mi;
      vy[j] += dy * mi;
      vz[j] += dz * mi;
    }
  }
  for (int i = 0; i < NBODY; ++i) {
    x[i] += dt * vx[i];
    y[i] += dt * vy[i];
    z[i] += dt * vz[i];
  }
}

static double energy(void) {
  double e = 0.0;
  for (int i = 0; i < NBODY; ++i) {
    e += 0.5 * mass[i] * (vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i]);
    for (int j = i + 1; j < NBODY; ++j) {
      double dx = x[i] - x[j];
      double dy = y[i] - y[j];
      double dz = z[i] - z[j];
      e -= (mass[i] * mass[j]) / sqrt(dx * dx + dy * dy + dz * dz);
    }
  }
  return e;
}

int main(void) {
  offset_momentum();
  for (int s = 0; s < STEPS; ++s) {
    advance(DT);
  }
  double e = energy();

  unsigned long long bits;
  memcpy(&bits, &e, sizeof(bits));
  printf("%llu\n", bits & 0x7fffffffffffffffULL);
  return 0;
}
