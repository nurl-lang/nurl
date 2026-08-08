// borrow_vec_free_with.nu — vec_free_with consumes its Vec.
//
// The destructor rule keyed on a `_free` SUFFIX, so `vec_free` was a
// consuming call and `vec_free_with` was not — even though it releases
// strictly more: the container and, through the dropper it is handed,
// every element. That is how the stdlib frees every Vec of owned
// elements, so the blind spot sat on the most common shape: reading a
// Vec after vec_free_with compiled clean and ran on freed memory.
//
// Expected: COMPILE FAIL — use of moved value 'v'.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a` ) )
    ( vec_free_with [String] v \ String s → v { ( string_free s ) } )
    ^ ( vec_len [String] v )
}
