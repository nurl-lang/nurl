// payload_cursor_of_an_uncopyable_payload_stored_into_a_literal_runs_clean: `?? o { T x → { : ~ cur x  : W q @ W { cur 0 } } }` over a `? R`, R with a `% Drop` of its own and no copy; o never read again
// AGORA-840 guard (CodeRabbit on github#1953): accepted - the literal takes the option's payload, released once, by q
// map: §2.12 | A2 | runs-clean | - | AGORA-840
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }

% Drop R {
    @ drop R r → v { ( nurl_println_int ( vec_len [i] . r v ) ) }
}

: W { R r i n }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    : ~ ? R o @ ?R { T @ R { xs } }
    ?? o {
        T x → {
            : ~ R cur x
            : W q @ W { cur 0 }
            ( nurl_println_int ( vec_len [i] . . q r v ) )
        }
        F → {}
    }
    ^ 0
}
