// foreach_element_scope.nu — a foreach's element is the loop's own
// (agora #245): after the loop the name is the outer binding it shadowed
// again. It used to stay the element, a view of the container's slot
// (tools/fuzz/holes/foreach_element_after_*.nu read it after the loop).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : String s ( string_from `the outer string` )
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 3 )
    ( vec_push [i] xs 4 )
    : ~ i sum 0
    ~ s xs { = sum + sum s }
    ( nurl_println_int sum )
    ( nurl_println ( string_data s ) )
    ^ 0
}
