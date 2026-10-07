// fib — recursive Fibonacci(35). Output: 9227465.
// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

fn fib(n: u64) -> u64 {
    if n < 2 {
        n
    } else {
        fib(n - 1) + fib(n - 2)
    }
}

fn main() {
    // BENCH_SCALE calls of fib(35), summed. The argument is 35 + (total >> 62):
    // always 35, but not provably constant, so the call cannot be hoisted.
    let mut total: u64 = 0;
    for _ in 0..BENCH_SCALE {
        total += fib(35 + (total >> 62));
    }
    println!("{}", total);
}
