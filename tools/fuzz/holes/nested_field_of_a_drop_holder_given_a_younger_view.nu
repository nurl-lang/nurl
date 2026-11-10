// nested_field_of_a_drop_holder_given_a_younger_view: a `% Drop H` holder given a nested view of a younger b: b is dropped first, and h's destructor reads it.
// Closed: a nested field store walks the root binding's own storage, so it keeps the view it stores in that binding (`__field_store_nested__`, the `=.` vpass row) as the one-level store does (agora #348).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | rejected | - | agora #348: a nested field store of a view records the holder's dependency on the source
$ `stdlib/core/string.nu`

: V { s v }
: H { V w }

% Drop H { @ drop H x → v { ( nurl_println . . x w v ) } }

@ main → i {
    : ~ H h @ H { @ V { `a literal` } }
    : String b ( string_from `a string younger than h, freed before h's destructor runs` )
    = . . h w v ( string_data b )
    ^ 0
}
