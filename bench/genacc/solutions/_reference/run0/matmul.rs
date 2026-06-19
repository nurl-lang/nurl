// matmul — multiply two 128x128 integer matrices, print the trace.
fn main() {
    let n = 128usize;
    let mut a = vec![0i64; n * n];
    let mut b = vec![0i64; n * n];
    let mut c = vec![0i64; n * n];

    for i in 0..n {
        for j in 0..n {
            let idx = i * n + j;
            a[idx] = (idx % 7) as i64;
            b[idx] = ((i + j) % 5) as i64;
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

    let mut tr = 0i64;
    for d in 0..n {
        tr += c[d * n + d];
    }
    println!("{}", tr);
}
