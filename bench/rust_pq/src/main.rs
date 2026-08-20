// bench/rust_pq/src/main.rs — the Rust half of the post-quantum peer
// comparison. Emits the same TSV rows as bench/pq_compare.nu:
//
//     ROW\t<name>\t<ns_per_op>\t<iters>
//     THR\t<name>\t<mb_per_s>
//
// The measurement discipline mirrors stdlib/std/bench.nu so the two
// columns are comparable: `bench_auto` ramps the iteration count 4x
// until a timed pass clears ~50 ms, then re-runs once calibrated onto
// that window; `bench_run` is a fixed-iteration run (SLH-DSA, whose
// single ops are already tens of milliseconds) with a short warmup.
// Randomness is SysRng — a getrandom(2) draw per operation, the same
// per-op OS-entropy discipline as the NURL side's nurl_rand_fill.
// Operation names must stay in lockstep with pq_compare.nu — the report
// generator joins on them.

use std::hint::black_box;
use std::time::Instant;

use crypto_common::getrandom::{rand_core::UnwrapErr, SysRng};
use crypto_common::Generate;
use ml_dsa::{Keypair, MlDsa44, MlDsa65, MlDsa87, MlDsaParams};
use ml_kem::kem::{Decapsulate, Encapsulate, Kem};
use ml_kem::{MlKem1024, MlKem512, MlKem768};
use shake::{ExtendableOutput, Shake128, Update, XofReader};
use signature::{RandomizedSigner, Verifier};
use slh_dsa::{Shake128f, Shake128s, Shake192f, Shake256f};

const TARGET_NS: u128 = 50_000_000; // bench.nu bench_auto target
const CAP: u64 = 100_000_000; //          … and its iteration cap

fn rng() -> UnwrapErr<SysRng> {
    UnwrapErr(SysRng)
}

fn timed(iters: u64, body: &mut impl FnMut()) -> u128 {
    // warmup: ~1% of iters, at least 1 (bench.nu bench_run)
    let warm = (iters / 100).max(1);
    for _ in 0..warm {
        body();
    }
    let t0 = Instant::now();
    for _ in 0..iters {
        body();
    }
    t0.elapsed().as_nanos()
}

fn row(name: &str, ns_per_op: u128, iters: u64) {
    println!("ROW\t{name}\t{ns_per_op}\t{iters}");
}

// bench.nu bench_run: fixed iteration count, warmup excluded.
fn bench_run(name: &str, iters: u64, mut body: impl FnMut()) {
    let total = timed(iters, &mut body);
    row(name, total / iters as u128, iters);
}

// bench.nu bench_auto: ramp 4x until a pass clears TARGET_NS, then one
// calibrated pass sized onto the target window.
fn bench_auto(name: &str, mut body: impl FnMut()) {
    let mut iters: u64 = 1;
    let mut total;
    loop {
        total = timed(iters, &mut body);
        if total >= TARGET_NS || iters >= CAP {
            break;
        }
        iters *= 4;
    }
    if total > TARGET_NS && iters > 1 && iters < CAP {
        let want = (iters as u128 * TARGET_NS / total) as u64;
        if want > 0 && want < iters {
            total = timed(want, &mut body);
            iters = want;
        }
    }
    row(name, total / iters as u128, iters);
}

fn msg(n: usize) -> Vec<u8> {
    (0..n).map(|i| ((i * 7) & 255) as u8).collect()
}

// SHAKE128 bulk absorb: 8 MB, one warmup pass, best of 3 timed passes
// (same shape as pq_compare.nu's __shake_bulk).
fn shake_bulk() {
    const MB: usize = 8;
    let buf = msg(MB * 1048576);
    let absorb = |b: &[u8]| {
        let mut h = Shake128::default();
        h.update(b);
        let mut out = [0u8; 32];
        h.finalize_xof().read(&mut out);
        out
    };
    black_box(absorb(&buf));
    let mut best = u128::MAX;
    for _ in 0..3 {
        let t0 = Instant::now();
        black_box(absorb(&buf));
        best = best.min(t0.elapsed().as_nanos());
    }
    let mb_s = (MB as u128) * 1000 * 1_000_000 / best;
    println!("THR\tSHAKE128 absorb 8 MB\t{mb_s}");
}

fn mlkem<K: Kem>(name: &str)
where
    K::DecapsulationKey: Decapsulate,
{
    let mut r = rng();
    bench_auto(&format!("{name} keygen"), || {
        black_box(K::generate_keypair_from_rng(&mut r));
    });
    let (dk, ek) = K::generate_keypair_from_rng(&mut r);
    bench_auto(&format!("{name} encaps"), || {
        black_box(ek.encapsulate_with_rng(&mut r));
    });
    let (ct, _ss) = ek.encapsulate_with_rng(&mut r);
    bench_auto(&format!("{name} decaps"), || {
        black_box(dk.decapsulate(&ct));
    });
}

fn mldsa<P: MlDsaParams>(name: &str) {
    let mut r = rng();
    bench_auto(&format!("{name} keygen"), || {
        black_box(ml_dsa::SigningKey::<P>::generate_from_rng(&mut r));
    });
    let sk = ml_dsa::SigningKey::<P>::generate_from_rng(&mut r);
    let m = msg(1024);
    // Hedged (randomized) signing with an empty context, like the NURL
    // side's mldsa_sign.
    bench_auto(&format!("{name} sign"), || {
        black_box(sk.expanded_key().sign_randomized(&m, &[], &mut r).unwrap());
    });
    let sig = sk.expanded_key().sign_randomized(&m, &[], &mut r).unwrap();
    let vk = sk.verifying_key();
    bench_auto(&format!("{name} verify"), || {
        vk.verify(&m, &sig).unwrap();
    });
}

fn slh<P: slh_dsa::ParameterSet>(name: &str, kgn: u64, sgn: u64, vfn: u64) {
    let mut r = rng();
    bench_run(&format!("{name} keygen"), kgn, || {
        black_box(slh_dsa::SigningKey::<P>::new(&mut r));
    });
    let sk = slh_dsa::SigningKey::<P>::new(&mut r);
    let m = msg(1024);
    // Randomized signing, like the NURL side's slhdsa_sign.
    bench_run(&format!("{name} sign"), sgn, || {
        black_box(sk.sign_with_rng(&mut r, &m));
    });
    let sig = sk.sign_with_rng(&mut r, &m);
    let vk = sk.verifying_key();
    bench_run(&format!("{name} verify"), vfn, || {
        vk.verify(&m, &sig).unwrap();
    });
}

fn main() {
    shake_bulk();
    mlkem::<MlKem512>("ML-KEM-512");
    mlkem::<MlKem768>("ML-KEM-768");
    mlkem::<MlKem1024>("ML-KEM-1024");
    mldsa::<MlDsa44>("ML-DSA-44");
    mldsa::<MlDsa65>("ML-DSA-65");
    mldsa::<MlDsa87>("ML-DSA-87");
    slh::<Shake128s>("SLH-DSA-SHAKE-128s", 3, 2, 10);
    slh::<Shake128f>("SLH-DSA-SHAKE-128f", 20, 5, 40);
    slh::<Shake192f>("SLH-DSA-SHAKE-192f", 10, 3, 20);
    slh::<Shake256f>("SLH-DSA-SHAKE-256f", 5, 2, 10);
}
