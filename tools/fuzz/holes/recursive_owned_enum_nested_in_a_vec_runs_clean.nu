// recursive_owned_enum_nested_in_a_vec_runs_clean: a recursive enum of owned strings nested through a Vec.
// The shape the fix must keep: a recursive enum that owns everything it holds is an owner of no view.
// main 24e95a81: runs clean.
// map: §2.13 | A2 | runs-clean | - | agora #338: a recursive enum of owned strings nested through a Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

: | Json { JStr String JArr ( Vec Json ) JNum i }

@ main → i {
    : ( Vec Json ) top ( vec_new [Json] )
    {
        : ( Vec Json ) inner ( vec_new [Json] )
        ( vec_push [Json] inner @ Json { JStr ( string_from `owned leaf string long enough` ) } )
        ( vec_push [Json] top @ Json { JArr inner } )
    }
    ?? ( vec_at [Json] top 0 ) { JArr xs → { ?? ( vec_at [Json] xs 0 ) { JStr w → ( nurl_println ( string_data w ) ) JArr ys → {} JNum n → {} } } JStr w → {} JNum n → {} }
    ^ 0
}
