// vec_given_back_a_lend_of_itself_through_a_block_binding_runs_clean: `: x { v }` binds a lend of an outer `v`, and `= v x` gives v that value back — over an owner, over one that owns its value on some paths only, and through a nested block (`: x { { v } }`).
// Closed (agora #667): `= v x` took x's value for another one and released v's old value, the very buffer it then stored back (heap-use-after-free). A binding bound as a lend (`__sborrow` `1` / `dyn`) is now asked by its key at `= o e`, as a cursor is: on the runs it holds o's own value, o keeps it. The elaborated twin of owned_vec_assigned_a_nested_value_block_of_itself reached it once that probe's join moved by name.
// map: §7.6 | A2 | runs-clean | - | agora #667: an owner given back a lend of itself through a block-bound binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f i c → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : __el { { v } }
    = v __el
    ( vec_push [String] v ( string_from `two` ) )
    ^ # i ( vec_len [String] v )
}

@ g i c ( Vec String ) h → i {
    : ~ ( Vec String ) v ? > c 0 ( vec_new [String] ) h
    : __el { { v } }
    = v __el
    ^ # i ( vec_len [String] v )
}

@ k i c → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : __el ? > c 0 v v
    = v __el
    : __e2 { v }
    = v __e2
    ( vec_push [String] v ( string_from `two` ) )
    ^ # i ( vec_len [String] v )
}

@ main → i {
    : ( Vec String ) h ( vec_new [String] )
    ( nurl_println_int ( f 1 ) ) ( nurl_println_int ( g 1 h ) ) ( nurl_println_int ( g 0 h ) ) ( nurl_println_int ( k 1 ) )
    ^ 0
}
