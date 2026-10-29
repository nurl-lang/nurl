// H750: agora #180 — a `?` arm block's tail field of the arm's own struct, returned (cond_arm_block_local_field_returned).
// Closed: an arm whose value is a field of a struct the arm owns itself moves it out of that struct (a struct with a `% Drop` of its own keeps a copy), so the arm's locals are dropped at its exit (mem_arm_take_field; agora #180).
// v0.80.0 and main: accepted; LeakSanitizer (the struct was never dropped).
$ `stdlib/core/string.nu`

: P { String s i n }

: | G {
    V P
    Nil
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part b c → String { ^ ? c { : P q @ P { ( mk ) 1 } . q s } ( mk ) }

@ main → i {
    : String t ( part T )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
