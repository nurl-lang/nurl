// benchmark-contract: nbody-symplectic-euler;bodies=5;steps=500000;dt=0.01;solar_mass=4*pi*pi;days_per_year=365.24;output=bits(energy)&(2^63-1)
//
// nbody — 500k symplectic-Euler steps of the Sun + four gas giants, then
// print the total energy of the system. Ten body pairs per step, each
// costing one sqrt and one divide: the only row in the suite whose
// critical path runs through the FPU's long-latency, non-pipelined units
// rather than the integer ALU.
//
// `sqrt` is declared straight against libm — `bench.sh` already links
// every NURL binary with `-lm`, so the row needs no stdlib import and
// stays a single self-contained file like its four peers.
//
// Struct-of-arrays rather than an array of structs: seven `*f` runs of
// five doubles. All 280 bytes live in L1 either way, so the layout does
// not move the number; it keeps the file readable against the Python and
// JavaScript ports, which are laid out the same way.
//
// Contract: the process prints exactly one line — the bit pattern of
// the final energy as a double, masked to 63 bits so the languages
// without an unsigned 64-bit type can print it too. The five ports
// evaluate the same operations in the same order, and +, -, *, / and
// sqrt are all correctly rounded by IEEE-754, so that line must agree
// to the bit across all five.

& `m` @ sqrt f x → f

@ main → i {
    : i STEPS 500000
    : f DT 0.01
    : f PI 3.141592653589793
    : f SOLAR_MASS * * 4.0 PI PI
    : f DPY 365.24

    : *f x # *f ( malloc 40 )
    : *f y # *f ( malloc 40 )
    : *f z # *f ( malloc 40 )
    : *f vx # *f ( malloc 40 )
    : *f vy # *f ( malloc 40 )
    : *f vz # *f ( malloc 40 )
    : *f mass # *f ( malloc 40 )

    // sun
    = . x 0 0.0
    = . y 0 0.0
    = . z 0 0.0
    = . vx 0 0.0
    = . vy 0 0.0
    = . vz 0 0.0
    = . mass 0 SOLAR_MASS

    // jupiter
    = . x 1 4.84143144246472090e+00
    = . y 1 -1.16032004402742839e+00
    = . z 1 -1.03622044471123109e-01
    = . vx 1 * 1.66007664274403694e-03 DPY
    = . vy 1 * 7.69901118419740425e-03 DPY
    = . vz 1 * -6.90460016972063023e-05 DPY
    = . mass 1 * 9.54791938424326609e-04 SOLAR_MASS

    // saturn
    = . x 2 8.34336671824457987e+00
    = . y 2 4.12479856412430479e+00
    = . z 2 -4.03523417114321381e-01
    = . vx 2 * -2.76742510726862411e-03 DPY
    = . vy 2 * 4.99852801234917238e-03 DPY
    = . vz 2 * 2.30417297573763929e-05 DPY
    = . mass 2 * 2.85885980666130812e-04 SOLAR_MASS

    // uranus
    = . x 3 1.28943695621391310e+01
    = . y 3 -1.51111514016986312e+01
    = . z 3 -2.23307578892655734e-01
    = . vx 3 * 2.96460137564761618e-03 DPY
    = . vy 3 * 2.37847173959480950e-03 DPY
    = . vz 3 * -2.96589568540237556e-05 DPY
    = . mass 3 * 4.36624404335156298e-05 SOLAR_MASS

    // neptune
    = . x 4 1.53796971148509165e+01
    = . y 4 -2.59193146099879641e+01
    = . z 4 1.79258772950371181e-01
    = . vx 4 * 2.68067772490389322e-03 DPY
    = . vy 4 * 1.62824170038242295e-03 DPY
    = . vz 4 * -9.51592254519715870e-05 DPY
    = . mass 4 * 5.15138902046611451e-05 SOLAR_MASS

    // ── offset_momentum ────────────────────────────────────────
    // Put the system in the barycentric frame: without this the Sun
    // drifts and the energy is not the conserved quantity the checksum
    // assumes.
    : ~ f px 0.0
    : ~ f py 0.0
    : ~ f pz 0.0
    : ~ i bi 0
    ~ < bi 5 {
        = px + px * . vx bi . mass bi
        = py + py * . vy bi . mass bi
        = pz + pz * . vz bi . mass bi
        = bi + bi 1
    }
    = . vx 0 / ~ px SOLAR_MASS
    = . vy 0 / ~ py SOLAR_MASS
    = . vz 0 / ~ pz SOLAR_MASS

    // ── advance × STEPS ────────────────────────────────────────
    : ~ i s 0
    ~ < s STEPS {
        = bi 0
        ~ < bi 5 {
            : ~ i bj + bi 1
            ~ < bj 5 {
                : f dx - . x bi . x bj
                : f dy - . y bi . y bj
                : f dz - . z bi . z bj
                : f d2 + + * dx dx * dy dy * dz dz
                : f mag / DT * d2 ( sqrt d2 )
                : f mi * . mass bi mag
                : f mj * . mass bj mag
                = . vx bi - . vx bi * dx mj
                = . vy bi - . vy bi * dy mj
                = . vz bi - . vz bi * dz mj
                = . vx bj + . vx bj * dx mi
                = . vy bj + . vy bj * dy mi
                = . vz bj + . vz bj * dz mi
                = bj + bj 1
            }
            = bi + bi 1
        }
        = bi 0
        ~ < bi 5 {
            = . x bi + . x bi * DT . vx bi
            = . y bi + . y bi * DT . vy bi
            = . z bi + . z bi * DT . vz bi
            = bi + bi 1
        }
        = s + s 1
    }

    // ── energy ─────────────────────────────────────────────────
    : ~ f e 0.0
    = bi 0
    ~ < bi 5 {
        : f v2 + + * . vx bi . vx bi * . vy bi . vy bi * . vz bi . vz bi
        = e + e * * 0.5 . mass bi v2
        : ~ i bj + bi 1
        ~ < bj 5 {
            : f dx - . x bi . x bj
            : f dy - . y bi . y bj
            : f dz - . z bi . z bj
            : f d2 + + * dx dx * dy dy * dz dz
            = e - e / * . mass bi . mass bj ( sqrt d2 )
            = bj + bj 1
        }
        = bi + bi 1
    }

    // Reinterpret the double's bits as i64 — a store through `*f` read
    // back through `*i` — and mask off the sign bit, so the peers
    // without an unsigned 64-bit type print the same decimal.
    : *f fp # *f ( malloc 8 )
    = . fp 0 e
    : *i ip # *i fp
    : i bits . ip 0
    ( nurl_println_int & bits 9223372036854775807 )

    ( free x )
    ( free y )
    ( free z )
    ( free vx )
    ( free vy )
    ( free vz )
    ( free mass )
    ( free fp )
    ^ 0
}
