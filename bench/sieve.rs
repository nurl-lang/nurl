// sieve — Sieve of Eratosthenes, count primes ≤ 10_000_000.
// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

fn main() {
    const N: usize = 10_000_000;
    let mut mark = vec![0u8; N];
    // BENCH_SCALE full sieves over the same buffer; the counts add up.
    let mut count: usize = 0;
    for rep in 0..BENCH_SCALE {
        if rep > 0 {
            mark.fill(0); // the first pass gets vec!'s zeroed allocation
        }
        mark[0] = 1;
        mark[1] = 1;
        let mut p: usize = 2;
        while p * p < N {
            if mark[p] == 0 {
                let mut m = p * p;
                while m < N {
                    mark[m] = 1;
                    m += p;
                }
            }
            p += 1;
        }
        let mut k: usize = 2;
        while k < N {
            if mark[k] == 0 {
                count += 1;
            }
            k += 1;
        }
    }
    println!("{}", count);
}
