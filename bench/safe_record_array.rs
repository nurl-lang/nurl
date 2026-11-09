// benchmark-contract: safe-record-array;records=4096;record=4xu64(key,val,hits,tag);steps=10000000;lcg=mmix(seed=1);draw=state>>33;ia=r&4095;ib=(r>>12)&4095;swap=(r>>24)&1;fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// safe_record_array — 10M by-value updates of a Vec of 4096 small
// records (see safe_record_array.nu for the shape). A `Vec<Rec>` of a
// `Copy` struct, bounds-checked indexing, `mix` and `bump` taking and
// returning their records by value: the safe-Rust spelling of the NURL
// row, no `unsafe`.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

#[derive(Clone, Copy)]
struct Rec {
    key: u64,
    val: u64,
    hits: u64,
    tag: u64,
}

#[derive(Clone, Copy)]
struct Pair {
    lo: u64,
    hi: u64,
}

fn mix(a: Rec, b: Rec, r: u64) -> Pair {
    Pair {
        lo: a.key ^ b.val ^ r,
        hi: a.val.wrapping_add(b.key).wrapping_mul(2654435761),
    }
}

fn bump(a: Rec, p: Pair) -> Rec {
    Rec {
        key: a.key ^ p.lo,
        val: a.val.wrapping_add(p.hi >> 3),
        hits: a.hits.wrapping_add(1),
        tag: (a.tag + (p.lo & 15)) & 255,
    }
}

fn fnv(h: u64, v: u64) -> u64 {
    (h ^ v).wrapping_mul(1099511628211)
}

fn main() {
    let steps = 10_000_000u64 * BENCH_SCALE;
    let n = 4096usize;
    let mut recs: Vec<Rec> = Vec::with_capacity(n);
    for z in 0..n {
        let zu = z as u64;
        recs.push(Rec { key: zu.wrapping_mul(2654435761), val: zu, hits: 0, tag: zu & 7 });
    }

    let mut x: u64 = 1;
    for _ in 0..steps {
        x = x
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        let r = x >> 33;
        let ia = (r & 4095) as usize;
        let ib = ((r >> 12) & 4095) as usize;
        let a = recs[ia];
        let b = recs[ib];
        let p = mix(a, b, r);
        recs[ia] = bump(a, p);
        if (r >> 24) & 1 == 1 {
            let t = recs[ia];
            let w = recs[ib];
            recs[ia] = w;
            recs[ib] = t;
        }
    }

    let mut h: u64 = 1469598103934665603;
    for e in &recs {
        h = fnv(h, e.key);
        h = fnv(h, e.val);
        h = fnv(h, e.hits);
        h = fnv(h, e.tag);
    }
    h = fnv(h, x);
    println!("{}", (h & 0x7fff_ffff_ffff_ffff) as i64);
}
