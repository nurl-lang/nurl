// matmul — multiply two 256x256 integer matrices, print the trace.
// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

fn main() {
    let n = 256usize;
    let mut a = vec![0i64; n * n];
    let mut b = vec![0i64; n * n];
    let mut c = vec![0i64; n * n];

    // BENCH_SCALE products, the inputs shifted by the repetition so no two
    // are the same computation; the traces add up.
    let mut tr = 0i64;
    for rep in 0..BENCH_SCALE as usize {
        for i in 0..n {
            for j in 0..n {
                let idx = i * n + j;
                a[idx] = ((idx + rep) % 7) as i64;
                b[idx] = ((i + j + rep) % 5) as i64;
            }
        }

        for ri in 0..n {
            for cj in 0..n {
                let mut s = 0i64;
                for k in 0..n {
                    s += a[ri * n + k] * b[k * n + cj];
                }
                c[ri * n + cj] = s;
            }
        }

        for d in 0..n {
            tr += c[d * n + d];
        }
    }
    println!("{}", tr);
}
