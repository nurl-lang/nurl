// benchmark-contract: captured-closure-queue;slots=16;kinds=5(add,mulxor,rotadd,table16,pair);steps=10000000;lcg=mmix(seed=1);draw=state>>33;slot=r&15;refill=every256th(slot=(r>>8)&15,kind=((r>>12)&65535)%5);chain=v=f(v^r);fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// captured_closure_queue — 10M calls through a queue of 16 closures with
// differently shaped captured environments (see captured_closure_queue.nu
// for the shape). The queue is a `Vec<Box<dyn Fn(u64) -> u64>>`: Rust
// closures of different capture shapes have different types, and a boxed
// `dyn Fn` is how one container holds them — the same { code, heap
// environment } pair a NURL closure is. The table kind captures a
// `Vec<u64>` and indexes it bounds-checked.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

type Clo = Box<dyn Fn(u64) -> u64>;

#[derive(Clone, Copy)]
struct Pair {
    lo: u64,
    hi: u64,
}

fn mk_add(c: u64) -> Clo {
    Box::new(move |x: u64| x.wrapping_add(c))
}

fn mk_mulxor(m: u64, s: u64) -> Clo {
    Box::new(move |x: u64| x.wrapping_mul(m) ^ s)
}

fn mk_rotadd(rot: u64, a: u64, b: u64) -> Clo {
    Box::new(move |x: u64| ((x >> rot) | (x << (64 - rot))).wrapping_add(a) ^ b)
}

fn mk_table(seed: u64) -> Clo {
    let mut t: Vec<u64> = Vec::with_capacity(16);
    for j in 0..16u64 {
        t.push((seed ^ j).wrapping_mul(2654435761).wrapping_add(j));
    }
    Box::new(move |x: u64| x ^ t[(x & 15) as usize])
}

fn mk_pair(p: Pair) -> Clo {
    Box::new(move |x: u64| x.wrapping_add(p.lo) ^ p.hi)
}

// A closure of kind 0..4, its captures drawn from `r`.
fn make(kind: u64, r: u64) -> Clo {
    match kind {
        0 => mk_add(r),
        1 => mk_mulxor(r | 1, r >> 5),
        2 => mk_rotadd((r & 31) + 1, r >> 7, r.wrapping_mul(3)),
        3 => mk_table(r),
        _ => mk_pair(Pair { lo: r, hi: r << 17 }),
    }
}

fn fnv(h: u64, v: u64) -> u64 {
    (h ^ v).wrapping_mul(1099511628211)
}

fn lcg(x: u64) -> u64 {
    x.wrapping_mul(6364136223846793005)
        .wrapping_add(1442695040888963407)
}

fn main() {
    let steps = 10_000_000u64 * BENCH_SCALE;
    let mut x: u64 = 1;
    let mut q: Vec<Clo> = Vec::with_capacity(16);
    for z in 0..16u64 {
        x = lcg(x);
        q.push(make(z % 5, x >> 33));
    }

    let mut v: u64 = 0;
    for k in 0..steps {
        x = lcg(x);
        let r = x >> 33;
        if k & 255 == 255 {
            q[((r >> 8) & 15) as usize] = make(((r >> 12) & 65535) % 5, r);
        }
        let f = &q[(r & 15) as usize];
        v = f(v ^ r);
    }

    let mut h: u64 = 1469598103934665603;
    h = fnv(h, v);
    for g in &q {
        h = fnv(h, g(12345));
    }
    h = fnv(h, x);
    println!("{}", (h & 0x7fff_ffff_ffff_ffff) as i64);
}
