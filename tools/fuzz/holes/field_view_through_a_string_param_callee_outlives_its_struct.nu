// field_view_through_a_string_param_callee_outlives_its_struct: agora #336 — #309's fifth shape: `( repoint w . h name )`, a String parameter's buffer stored whole into an `inout` holder, `h` a block's struct; the holder read after the block (closed by #309).
// Closed: storage the caller holds (a parameter) given whole a view of a binding the function releases is refused at every `^`, as where the body's scope ends (bck_param_view_check's borrower clause; agora #336, after #309).
// main: rejected.
// map: §2.10 | A2 | rejected | - | agora #336: a struct field's buffer stored by a callee into an inout holder
$ `stdlib/core/string.nu`

: W { s v }
: H { String name }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : H h @ H { ( string_from `a block's struct's name, freed at its end` ) }
        ( repoint w . h name )
    }
    ( nurl_println . w v )
    ^ 0
}
