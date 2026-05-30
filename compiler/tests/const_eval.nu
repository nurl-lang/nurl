// const_eval.nu — acceptance test for narrow compile-time constant
// folding of integer-typed top-level consts (gen_const_decl /
// const_eval_int). Before this, `: i NAME <expr>` accepted only a single
// literal; arithmetic on literals (the INT_MIN two's-complement, seconds
// tables, bit masks, …) had to be wrapped in a niladic function.
//
// Determinism: every value is fixed at compile time. ASan-clean.

: i SECS_PER_DAY * * 60 60 24
: i INT_MIN - -9223372036854775807 1
: i ONE_MB << 1 20
: i LOW_BYTE & 4660 255
: i HIGH_OR | 240 15
: i XORED ^^ 12 10
: i NESTED + * 3 4 - 10 2
: i32 NARROW * 7 6
: i SHIFTED_DOWN >> 1024 4

@ ck s label i got i want → v {
    ( nurl_print label )
    ( nurl_print ? == got want ` ok = ` ` MISMATCH = ` )
    ( nurl_print_int got )
}

@ main → i {
    ( ck `secs_per_day` SECS_PER_DAY 86400 )
    ( ck `int_min     ` INT_MIN - -9223372036854775807 1 )
    ( ck `one_mb      ` ONE_MB 1048576 )
    ( ck `low_byte    ` LOW_BYTE 52 )
    ( ck `high_or     ` HIGH_OR 255 )
    ( ck `xored       ` XORED 6 )
    ( ck `nested      ` NESTED 20 )
    ( ck `narrow_i32  ` # i NARROW 42 )
    ( ck `shifted_down` SHIFTED_DOWN 64 )
    ^ 0
}
