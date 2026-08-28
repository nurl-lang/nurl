// quicksort — sort 5000 LCG-generated ints in place, print a
// position-weighted checksum (sum of (k+1)*a[k]) that only comes out
// right if the array is actually sorted. Recursion + array mutation.
@ swap *i a i p i q → v {
    : i t . a p
    = . a p . a q
    = . a q t
}

@ qsort *i a i lo i hi → v {
    ? < lo hi {
        : i pivot . a hi
        : ~ i st lo
        : ~ i j lo
        ~ < j hi {
            ? < . a j pivot { ( swap a st j ) = st + st 1 } {}
            = j + j 1
        }
        ( swap a st hi )
        ( qsort a lo - st 1 )
        ( qsort a + st 1 hi )
    } {}
}

@ main → i {
    : i N 5000
    : *i a # *i ( malloc * N 8 )
    : ~ i x 1
    : ~ i i 0
    ~ < i N {
        = x % + * x 1103515245 12345 1048576
        = . a i x
        = i + i 1
    }
    ( qsort a 0 - N 1 )
    : ~ i sum 0
    : ~ i k 0
    ~ < k N {
        = sum + sum * + k 1 . a k
        = k + k 1
    }
    ( nurl_println_int sum )
    ( free a )
    ^ 0
}
