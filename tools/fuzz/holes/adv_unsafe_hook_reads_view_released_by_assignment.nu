// map: §2.14 | A2 | rejected | - | AGORA-384: adversarial neighbour of the destructor-as-effect rule (a384_unsafe_hook_reads_view_released_by_assignment)
// AGORA-384 (closed): refused - a drop hook of the program's own may read the views its value holds, as a `% Drop` may (main 2c54f01f: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`

: H { s v }

@ H_drop sink H h → v { ( nurl_println . h v ) }

@ main → i {
    : ~ H h @ H { `literal` }
    ? T {
        : String b ( string_from `a string of an inner block, freed before the hook runs` )
        = h @ H { ( string_data b ) }
    } {}
    = h @ H { `another` }
    ^ 0
}
