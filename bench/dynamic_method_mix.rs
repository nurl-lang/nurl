// benchmark-contract: dynamic-method-mix;objects=64;impls=4(adder,mixer,shifter,lookup16);kind=(r>>8)%4;steps=10000000;lcg=mmix(seed=1);draw=state>>33;obj=r&63;chain=v=apply(o,v^r)+weight(o);fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// dynamic_method_mix — 10M steps over 64 trait objects behind one
// two-method interface (see dynamic_method_mix.nu for the shape): a
// `Vec<Box<dyn Op>>` of four implementing types, the lookup type owning
// a `Vec<u64>` it indexes bounds-checked.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

trait Op {
    fn apply(&self, x: u64) -> u64;
    fn weight(&self) -> u64;
}

struct Adder {
    c: u64,
}

struct Mixer {
    m: u64,
    s: u64,
}

struct Shifter {
    a: u64,
    b: u64,
    c: u64,
}

struct Lookup {
    t: Vec<u64>,
}

impl Op for Adder {
    fn apply(&self, x: u64) -> u64 {
        x.wrapping_add(self.c)
    }
    fn weight(&self) -> u64 {
        self.c & 7
    }
}

impl Op for Mixer {
    fn apply(&self, x: u64) -> u64 {
        x.wrapping_mul(self.m) ^ self.s
    }
    fn weight(&self) -> u64 {
        self.s & 7
    }
}

impl Op for Shifter {
    fn apply(&self, x: u64) -> u64 {
        ((x >> self.a) ^ (x << self.b)).wrapping_add(self.c)
    }
    fn weight(&self) -> u64 {
        self.a
    }
}

impl Op for Lookup {
    fn apply(&self, x: u64) -> u64 {
        x ^ self.t[(x & 15) as usize]
    }
    fn weight(&self) -> u64 {
        self.t[0] & 7
    }
}

fn lookup_table(seed: u64) -> Vec<u64> {
    let mut t = Vec::with_capacity(16);
    for j in 0..16u64 {
        t.push((seed ^ j).wrapping_mul(2654435761).wrapping_add(j));
    }
    t
}

// An object of kind 0..3, its fields drawn from `r`.
fn make(kind: u64, r: u64) -> Box<dyn Op> {
    match kind {
        0 => Box::new(Adder { c: r }),
        1 => Box::new(Mixer { m: r | 1, s: r >> 5 }),
        2 => Box::new(Shifter { a: (r & 31) + 1, b: ((r >> 5) & 31) + 1, c: r.wrapping_mul(3) }),
        _ => Box::new(Lookup { t: lookup_table(r) }),
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
    let mut objs: Vec<Box<dyn Op>> = Vec::with_capacity(64);
    for _ in 0..64 {
        x = lcg(x);
        let r = x >> 33;
        objs.push(make((r >> 8) % 4, r));
    }

    let mut v: u64 = 0;
    for _ in 0..steps {
        x = lcg(x);
        let r = x >> 33;
        let o = &objs[(r & 63) as usize];
        v = o.apply(v ^ r).wrapping_add(o.weight());
    }

    let mut h: u64 = 1469598103934665603;
    h = fnv(h, v);
    for g in &objs {
        h = fnv(h, g.apply(12345).wrapping_add(g.weight()));
    }
    h = fnv(h, x);
    println!("{}", (h & 0x7fff_ffff_ffff_ffff) as i64);
}
