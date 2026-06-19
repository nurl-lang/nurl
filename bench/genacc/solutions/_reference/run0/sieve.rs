// sieve — Sieve of Eratosthenes, count primes ≤ 10_000_000.
fn main() {
    const N: usize = 10_000_000;
    let mut mark = vec![0u8; N];
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
    let mut count: usize = 0;
    let mut k: usize = 2;
    while k < N {
        if mark[k] == 0 {
            count += 1;
        }
        k += 1;
    }
    println!("{}", count);
}
