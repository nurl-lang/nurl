// map: §2.12 | A2 | runs-clean | - | AGORA-840 item 3: `: ~ String cur ? == k 1 a b  ( vec_push [String] d cur )` - the join cursor pushed: the store copies, and the hand-on of a and b leaks one of them (strict LSan)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `a string long enough to be on the heap for certain` )
    : String b ( string_from `another string long enough to be on the heap too` )
    : ( Vec String ) d ( vec_new [String] )
    : i k ( nurl_str_len `x` )
    : ~ String cur ? == k 1 a b
    ( vec_push [String] d cur )
    ( nurl_println ( string_data ( vec_at [String] d 0 ) ) )
    ^ 0
}
