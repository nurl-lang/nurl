// benchmark-contract: payload-state-machine;events=10000000;lcg=mmix(seed=1);draw=state>>29;sel=r&7(0-2:Add,3:Scale,4:Push,5:Pop,6-7:Probe);max_depth=16;fault=DepthLow(String)|DepthHigh(u64,String);fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// payload_state_machine — 10M events through a state machine whose step
// returns `Result<St, Fault>`, the fault carrying an owned `String`
// (see payload_state_machine.nu for the shape). Enums with payloads,
// `Option`, `Result` and `match`: the Rust spelling of the NURL row.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

#[derive(Clone, Copy)]
struct St {
    acc: u64,
    depth: u64,
    steps: u64,
}

enum Ev {
    Add(u64),
    Scale(u64, u64),
    Push,
    Pop,
    Probe(u64),
}

enum Fault {
    DepthLow(String),
    DepthHigh(u64, String),
}

fn decode(r: u64) -> Ev {
    let sel = r & 7;
    let rest = r >> 3;
    if sel < 3 {
        return Ev::Add(rest & 65535);
    }
    if sel == 3 {
        return Ev::Scale((rest & 7) + 1, (rest >> 3) & 255);
    }
    if sel == 4 {
        return Ev::Push;
    }
    if sel == 5 {
        return Ev::Pop;
    }
    Ev::Probe(rest)
}

fn lookup(key: u64) -> Option<u64> {
    if key & 3 == 0 {
        return None;
    }
    Some(key.wrapping_mul(31))
}

// The fault's message: a fixed text and one byte chosen by the state.
fn fault_text(base: &str, acc: u64, c0: u64) -> String {
    let mut m = String::from(base);
    m.push((c0 + (acc & 15)) as u8 as char);
    m
}

fn step(s: St, e: Ev) -> Result<St, Fault> {
    match e {
        Ev::Add(v) => Ok(St { acc: s.acc.wrapping_add(v), depth: s.depth, steps: s.steps + 1 }),
        Ev::Scale(m, b) => Ok(St {
            acc: s.acc.wrapping_mul(m).wrapping_add(b),
            depth: s.depth,
            steps: s.steps + 1,
        }),
        Ev::Push => {
            if s.depth >= 16 {
                return Err(Fault::DepthHigh(s.depth, fault_text("stack overflow at ", s.acc, 65)));
            }
            Ok(St { acc: s.acc, depth: s.depth + 1, steps: s.steps + 1 })
        }
        Ev::Pop => {
            if s.depth == 0 {
                return Err(Fault::DepthLow(fault_text("stack underflow at ", s.acc, 97)));
            }
            Ok(St { acc: s.acc ^ s.depth, depth: s.depth - 1, steps: s.steps + 1 })
        }
        Ev::Probe(k) => match lookup(k) {
            Some(v) => Ok(St { acc: s.acc ^ v, depth: s.depth, steps: s.steps + 1 }),
            None => Ok(St { acc: s.acc.wrapping_add(1), depth: s.depth, steps: s.steps + 1 }),
        },
    }
}

fn fnv(h: u64, v: u64) -> u64 {
    (h ^ v).wrapping_mul(1099511628211)
}

// What a handler takes from a fault's message: its length and last byte.
fn text_sum(m: &str) -> u64 {
    let b = m.as_bytes();
    b.len() as u64 + b[b.len() - 1] as u64
}

fn main() {
    let events = 10_000_000u64 * BENCH_SCALE;
    let mut st = St { acc: 1, depth: 0, steps: 0 };
    let mut x: u64 = 1;
    let mut errh: u64 = 1469598103934665603;
    let mut faults: u64 = 0;
    for _ in 0..events {
        x = x
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        let ev = decode(x >> 29);
        match step(st, ev) {
            Ok(ns) => st = ns,
            Err(f) => {
                match f {
                    Fault::DepthLow(m) => errh = fnv(errh, text_sum(&m)),
                    Fault::DepthHigh(d, m) => errh = fnv(errh, d.wrapping_add(text_sum(&m))),
                }
                faults += 1;
                st = St { acc: st.acc.rotate_right(7), depth: 0, steps: st.steps };
            }
        }
    }
    let mut h: u64 = 1469598103934665603;
    h = fnv(h, st.acc);
    h = fnv(h, st.depth);
    h = fnv(h, st.steps);
    h = fnv(h, errh);
    h = fnv(h, faults);
    println!("{}", (h & 0x7fff_ffff_ffff_ffff) as i64);
}
