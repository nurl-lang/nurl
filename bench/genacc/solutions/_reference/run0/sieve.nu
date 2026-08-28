// sieve — Sieve of Eratosthenes, count primes ≤ 10_000_000.
// Allocates a 10 MB byte buffer (mark[0..N] with 0 = prime, 1 = composite),
// scans for primes ≤ √N marking multiples, then counts the zeros.
& `c` @ memset s buf i v i sz → s

@ main → i {
    : i n 10000000
    : s buf ( malloc n )
    ( memset buf 0 n )
    : *u p # *u buf
    = . p 0 # u 1
    = . p 1 # u 1

    : ~ i pr 2
    ~ < * pr pr n {
        ? == & 255 # i . p pr 0
        {
            : ~ i m * pr pr
            ~ < m n {
                = . p m # u 1
                = m + m pr
            }
        } {}
        = pr + pr 1
    }

    : ~ i count 0
    : ~ i k 2
    ~ < k n {
        ? == & 255 # i . p k 0 { = count + count 1 } {}
        = k + k 1
    }
    ( nurl_println_int count )
    ( free buf )
    ^ 0
}
