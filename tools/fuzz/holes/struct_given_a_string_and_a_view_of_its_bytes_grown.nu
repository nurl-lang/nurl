// struct_given_a_string_and_a_view_of_its_bytes_grown: a String and a view of its bytes in one struct, the String grown with string_push_str.
// Closed: a value given an owner and a view of that owner at once is refused where it is built — A2's SelfFree (ViewsOK.dropSelf): the store of b into o meets o's dependency on b (bck_diag_self_view; agora #294).
// main 2c20c888: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #294: a value that views its own field
$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`

: TS { ( Slice u ) v String s }

@ main → i {
    : String b ( string_from `a string long enough for a heap buffer here` )
    : ( Slice u ) sv ( string_bytes b )
    : ~ TS o @ TS { sv b }
    ( string_push_str . o s `and grown well past its first capacity, so that it moves` )
    ( nurl_println_int # i ( slice_at [u] . o v 0 ) )
    ^ 0
}
