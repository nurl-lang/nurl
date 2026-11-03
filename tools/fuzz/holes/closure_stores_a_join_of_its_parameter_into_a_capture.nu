// closure_stores_a_join_of_its_parameter_into_a_capture: a closure binds a join of its view parameter and a literal, then stores it into a struct it captures, read after the caller's String is gone.
// Closed: in a closure body, a join or a match bound reads what its source expression names, so a view of the closure's parameter through a join is that parameter's view, refused when stored into a capture as the plain one is (agora #448).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #448: a closure binds a join of its view parameter and a literal, then stores it into a struct it captures, read after the caller's String is gone
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: V { s v }

@ setv inout V x s t → v { = x @ V { t } }

@ main → i {
    : ~ V w @ V { `lit` }
    : ( @ v s ) setw \ s p → v { : s t ? > ( nurl_str_len p ) 0 p `x` = w @ V { t } }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        ( setw ( string_data b ) )
    }
    ( nurl_println . w v )
    ^ 0
}
