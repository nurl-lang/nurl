// map: §7.6 | A2 | runs-clean | - | agora #841: `: ~ [i r p  ? c { = r [i | 5 6] } {}  ^ r`: one return of a cursor slice that owns on some paths; the fresh one leaks
$ `stdlib/core/string.nu`

@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }

@ pick b c [i p → [i {
    : ~ [i r p
    ? c { = r [i | 5 6] } {}
    ^ r
}

@ main → i {
    : [i a [i | 1 2]
    : [i b ( pick T a )
    ( nurl_println_int + ( sum a ) ( sum b ) )
    ^ 0
}
