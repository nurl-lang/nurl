// struct_holding_string_and_its_bytes_grown: agora #294 — a String and a view of its bytes in one value, the String grown by `string_push_str` (struct_holding_string_and_its_bytes_grown).
// Closed: as for a Vec field (bck_views_part).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #294: a String and a view of its bytes in one value, the String grown by `string_push_str`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
: TS { ( Slice u ) v String s }
@ main → i {
    : String b ( string_from `a heap string long enough to be on the heap` )
    : ( Slice u ) sv ( string_bytes b )
    : TS o @ TS { sv b }
    ( string_push_str . o s ` and grown well past its first capacity, many times over` )
    ( nurl_println_int # i ( slice_at [u] . o v 0 ) )
    ^ 0
}
