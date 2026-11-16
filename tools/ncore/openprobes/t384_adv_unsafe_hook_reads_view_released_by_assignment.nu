// map: §2.14 | A2 | rejected | - | agora #384: adversarial neighbour of the destructor-as-effect rule (a384_unsafe_hook_reads_view_released_by_assignment)
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
