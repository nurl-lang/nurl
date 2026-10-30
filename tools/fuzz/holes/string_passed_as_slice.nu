// string_passed_as_slice: a pointer passed where a parameter is a struct by value — in safe code a string (`s`, a char pointer) into a `( Slice u )` parameter — compiled to an ill-typed call: the callee read the address as the slice's data and whatever followed in the registers as its length, then indexed that far. Every other pointer/value pairing was checked (a `*T` for its own `T`, a String for an `s`, two named types); a pointer against an unrelated struct was not (anomaly's imp_span_of_text passed its text where the byte view belonged).
// Closed: a pointer is rejected where a struct is passed by value, and a struct where a pointer is declared.
// main's compiler: a slice of garbage length over a short string — heap-buffer-overflow.
// map: §6.2 | B | rejected | h268 | raw string pointer passed where a Slice struct is expected (type confusion)
$ `stdlib/core/io.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`

@ count_digits ( Slice u ) t → i {
    : ~ i n 0
    : ~ i k 0
    ~ < k ( slice_len [u] t ) {
        : u c ( slice_at [u] t k )
        ? & >= c 48 <= c 57 { = n + n 1 } {}
        = k + k 1
    }
    ^ n
}

@ main → i {
    : String t ( string_from `90s` )
    : s p ( string_data t )
    ( nurl_println_int ( count_digits p ) )
    ^ 0
}
