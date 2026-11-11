// enum_payload_read_before_the_enum_is_handed_to_a_sink_runs_clean: a `??` arm that reads its payloads and then hands the matched enum binding to a `sink`; an integer payload read after the handover; the enum handed over in one arm and read in another; a fresh enum each round of a loop.
// Guard for agora #641's handover rule (a binding handed over whole ends the payloads its arm bound): only a read after the handover, of a payload that is part of the enum's storage, is refused.
// main c8c3f4d: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #641 guard: ?? payloads read before the enum is handed to a sink, an integer payload read after, and a handover in another arm stay accepted
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Three Bomb String Bomb }

@ mk3 → E { ^ @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

: | D { Dzero i Dthree Bomb String Bomb }

% Drop D { @ drop D d → v { ( nurl_println `drop D` ) } }

@ mkd → D { ^ @ D { Dthree ( bomb `d.a` ) ( string_from `3s, long enough for the heap` ) ( bomb `d.c` ) } }

@ eat sink E e → v { ( nurl_println `eat` ) }

@ eatd sink D d → v { ( nurl_println `eatd` ) }

@ main → i {
    : E e ( mk3 )
    ?? e {
        Zero n → { ( eat e ) ( nurl_println ( nurl_str_int n ) ) }
        Three x s y → {
            ( nurl_println ( nurl_str_cat3 ( string_data s ) ` ` ( string_data . y tag ) ) )
            ( eat e )
        }
    }
    : E z @ E { Zero 7 }
    ?? z {
        Zero n → { ( eat z ) ( nurl_println ( nurl_str_int n ) ) }
        Three x s y → { ( nurl_println ( string_data s ) ) }
    }
    : ~ i k 0
    ~ < k 2 {
        : D d ( mkd )
        ?? d {
            Dzero n → { ( eatd d ) }
            Dthree x s y → {
                ( nurl_println ( string_data . y tag ) )
                ( eatd d )
            }
        }
        = k + k 1
    }
    : D f ( mkd )
    ?? f {
        Dzero n → {}
        Dthree x s y → { ( nurl_println ( string_data s ) ) }
    }
    ( eatd f )
    ^ 0
}
