// diag_match_tf_on_struct.nu — 'T x →' / 'F e →' arms on a '??' whose
// scrutinee is neither an option nor a result.
//
// A String (or any struct) has no payload for 'T s' to bind. The arm
// used to get an empty binding type, nurlc exited 0, and clang reported
// "Cannot allocate unsized type" about generated IR. The diagnostic now
// names the scrutinee's type and the two shapes these arms belong to.
//
// Expected: COMPILE FAIL at the 'T' arm.

$ `stdlib/core/string.nu`

@ main → i {
    ?? ( string_from `x` ) {
        T s → { ( nurl_print `t` ) }
        F e → { ( nurl_print `f` ) }
    }
    ^ 0
}
