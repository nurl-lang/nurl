// bench/tls_bench/rust/src/bin/tls_prims.rs — the Rust half of the TLS
// primitive table: the same operations as bench/tls_bench/prims.nu, on
// aws-lc-rs (the provider rustls and tls_server use), timed the way
// stdlib/std/bench.nu's bench_auto times the NURL ones — ramp 4x until a
// pass clears ~50 ms, then one pass calibrated onto that window.
//
//     ROW\t<name>\t<ns_per_op>\t<iters>
//
// Names stay in lockstep with prims.nu.

use std::hint::black_box;
use std::time::Instant;

use aws_lc_rs::aead::{Aad, LessSafeKey, Nonce, UnboundKey, AES_128_GCM, CHACHA20_POLY1305};
use aws_lc_rs::agreement::{self, PrivateKey, UnparsedPublicKey, ECDH_P256, X25519};
use aws_lc_rs::kem::{DecapsulationKey, ML_KEM_768};
use aws_lc_rs::rand::{SecureRandom, SystemRandom};
use aws_lc_rs::rsa::KeySize;
use aws_lc_rs::signature::{self, EcdsaKeyPair, KeyPair, RsaKeyPair, ECDSA_P256_SHA256_ASN1_SIGNING};
use aws_lc_rs::{digest, hkdf};

const TARGET_NS: u128 = 50_000_000;
const CAP: u64 = 100_000_000;

fn timed(iters: u64, body: &mut impl FnMut()) -> u128 {
    for _ in 0..(iters / 100).max(1) {
        body();
    }
    let t0 = Instant::now();
    for _ in 0..iters {
        body();
    }
    t0.elapsed().as_nanos()
}

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
    println!("ROW\t{name}\t{}\t{iters}", total / iters as u128);
}

fn rand(n: usize) -> Vec<u8> {
    let mut v = vec![0u8; n];
    SystemRandom::new().fill(&mut v).unwrap();
    v
}

fn main() {
    let rng = SystemRandom::new();

    // ── key exchange ────────────────────────────────────────────────
    for (alg, kg, sh) in [
        (&X25519, "X25519 keygen", "X25519 shared"),
        (&ECDH_P256, "P-256 ECDH keygen", "P-256 ECDH shared"),
    ] {
        bench_auto(kg, || {
            let k = PrivateKey::generate(alg).unwrap();
            black_box(k.compute_public_key().unwrap());
        });
        let peer = PrivateKey::generate(alg).unwrap().compute_public_key().unwrap();
        let peer = UnparsedPublicKey::new(alg, peer.as_ref().to_vec());
        let mine = PrivateKey::generate(alg).unwrap();
        bench_auto(sh, || {
            agreement::agree(&mine, &peer, (), |s| {
                black_box(s);
                Ok(())
            })
            .unwrap();
        });
    }
    let dk = DecapsulationKey::generate(&ML_KEM_768).unwrap();
    let ek = dk.encapsulation_key().unwrap();
    bench_auto("ML-KEM-768 encaps", || {
        black_box(ek.encapsulate().unwrap());
    });

    // ── CertificateVerify ───────────────────────────────────────────
    // TLS signs a 130-byte content (64 spaces, context, 0, the 32-byte
    // transcript hash); aws-lc-rs hashes it inside sign().
    let msg = rand(130);
    let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, &rng).unwrap();
    let ec = EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, pkcs8.as_ref()).unwrap();
    bench_auto("ECDSA P-256 sign", || {
        black_box(ec.sign(&rng, &msg).unwrap());
    });
    let sig = ec.sign(&rng, &msg).unwrap();
    let pubk = signature::UnparsedPublicKey::new(&signature::ECDSA_P256_SHA256_ASN1, ec.public_key().as_ref().to_vec());
    bench_auto("ECDSA P-256 verify", || {
        black_box(pubk.verify(&msg, sig.as_ref()).is_ok());
    });
    let rsa = RsaKeyPair::generate(KeySize::Rsa2048).unwrap();
    let mut rsig = vec![0u8; rsa.public_modulus_len()];
    bench_auto("RSA-2048 PSS sign", || {
        rsa.sign(&signature::RSA_PSS_SHA256, &rng, &msg, &mut rsig).unwrap();
        black_box(&rsig);
    });

    // ── key schedule ────────────────────────────────────────────────
    let prk = hkdf::Prk::new_less_safe(hkdf::HKDF_SHA256, &rand(32));
    let ctx = rand(32);
    let label = b"tls13 c hs traffic";
    bench_auto("HKDF-Expand-Label", || {
        let len = [0u8, 32];
        let ll = [label.len() as u8];
        let cl = [ctx.len() as u8];
        let info: [&[u8]; 5] = [&len, &ll, label, &cl, &ctx];
        let mut out = [0u8; 32];
        prk.expand(&info, hkdf::HKDF_SHA256).unwrap().fill(&mut out).unwrap();
        black_box(out);
    });
    let blk = rand(16384);
    bench_auto("SHA-256 16 KB", || {
        black_box(digest::digest(&digest::SHA256, &blk));
    });

    // ── record layer: one full 16 KB record sealed in place ─────────
    for (alg, klen, name) in [
        (&AES_128_GCM, 16, "AES-128-GCM seal 16 KB"),
        (&CHACHA20_POLY1305, 32, "ChaCha20-Poly1305 seal 16 KB"),
    ] {
        let key = LessSafeKey::new(UnboundKey::new(alg, &rand(klen)).unwrap());
        let hdr = rand(5);
        let mut rec = rand(16384);
        let mut seq: u64 = 0;
        bench_auto(name, || {
            let mut n = [0u8; 12];
            n[4..].copy_from_slice(&seq.to_be_bytes());
            seq += 1;
            let tag = key
                .seal_in_place_separate_tag(Nonce::assume_unique_for_key(n), Aad::from(&hdr), &mut rec)
                .unwrap();
            let _ = black_box(tag);
        });
    }
}
