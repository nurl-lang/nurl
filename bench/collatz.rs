// collatz — longest Collatz chain length for starts in [1, 100000).
fn steps(mut n: u64) -> u64 {
    let mut c = 0;
    while n > 1 {
        n = if n % 2 == 0 { n / 2 } else { 3 * n + 1 };
        c += 1;
    }
    c
}

fn main() {
    let mut best = 0;
    for k in 1..100000 {
        let s = steps(k);
        if s > best {
            best = s;
        }
    }
    println!("{}", best);
}
