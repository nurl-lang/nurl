// generic_copy_of_a_value_it_cannot_copy: a generic that copies its `T` — `( box_clone [Res] b )`, built on `mem_dup` — instantiated with a value that cannot be copied (a `% Drop` value with no clone) copied its bits: two boxes, one buffer, released twice.
// Closed: `mem_dup` of such a value is rejected at the instantiation.
// main (before this PR): ASan heap-use-after-free.
// map: §7.6 | A2 | rejected | h235 | box_clone (mem_dup) of %Drop value copies bits: double free
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

$ `stdlib/core/box.nu`

@ main → i {
    : ( Box Res ) b ( box_new [Res] @ Res { ( vec_new [i] ) } )
    : ( Box Res ) c ( box_clone [Res] b )
    ^ 0
}
