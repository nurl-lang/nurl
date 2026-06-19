// quicksort — sort 5000 LCG ints in place, print a position-weighted checksum.
fn qsort(a: &mut [i64], lo: i64, hi: i64) {
    if lo >= hi {
        return;
    }
    let pivot = a[hi as usize];
    let mut st = lo;
    for j in lo..hi {
        if a[j as usize] < pivot {
            a.swap(st as usize, j as usize);
            st += 1;
        }
    }
    a.swap(st as usize, hi as usize);
    qsort(a, lo, st - 1);
    qsort(a, st + 1, hi);
}

fn main() {
    let n = 5000i64;
    let mut a = vec![0i64; n as usize];
    let mut x = 1i64;
    for i in 0..n as usize {
        x = (x * 1103515245 + 12345) % 1048576;
        a[i] = x;
    }
    qsort(&mut a, 0, n - 1);
    let mut total = 0i64;
    for k in 0..n as usize {
        total += (k as i64 + 1) * a[k];
    }
    println!("{}", total);
}
