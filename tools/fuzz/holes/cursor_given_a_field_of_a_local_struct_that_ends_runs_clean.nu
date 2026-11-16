// cursor_given_a_field_of_a_local_struct_that_ends_runs_clean: control: `= c . r sig` with r a local of an inner block: nurlc takes the field out, the cursor owns it after r ends
// AGORA-869 (fpA-r8): the ownership engine's rule for it; the walk's verdict is the same.
// map: §7.6 | A2 | runs-clean | - | control: `= c . r sig` with r a local of an inner block: nurlc takes the field out, the cursor owns it after r ends
$ `stdlib/core/string.nu`

: R { String a i ok String sig }

@ mk → R { ^ @ R { ( string_from `client final long enough for heap` ) 1 ( string_from `server signature long enough for heap` ) } }

@ main → i {
    : ~ String c ( string_with_cap 0 )
    : ~ i k 0
    ~ < k 2 {
        ? == k 0 {
            : R r ( mk )
            = c . r sig
        } {
            ( nurl_println ( string_data c ) )
        }
        = k + k 1
    }
    ^ 0
}
