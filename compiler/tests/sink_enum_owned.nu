// Compiler-managed enum owners transfer to sinks, including forward calls,
// forwarding, branch-local consumption and temporary/result payloads.
$ `stdlib/core/string.nu`

: Detail { String text i code }
: | Owned { OwnedLive Detail OwnedEmpty }

@ make → Owned { ^ @ Owned { OwnedLive @ Detail { ( string_from `owned` ) 503 } } }

@ pass sink Owned error → i { ^ ( take error ) }

@ take sink Owned error → i {
    ?? error { OwnedLive detail → { ^ + . detail code ( string_len . detail text ) } OwnedEmpty → { ^ 0 } }
}

@ release sink Owned error → v {}

@ choose b handoff → i {
    : Owned value ( make )
    ? handoff { ^ ( take value ) } {}
    ^ 0
}

@ failure → !i Owned { ^ @ !i Owned { F ( make ) } }

@ identity sink Owned error → Owned { ^ error }

@ fall_identity sink Owned error → Owned { error }

@ read_inout inout Owned error → i { ^ ( inspect error ) }

@ main → i {
    : ~ i failures 0
    : ~ i k 0
    ~ < k 100 {
        : Owned first ( make )
        ? != ( pass first ) 508 { = failures + failures 1 } {}
        : Owned second ( make )
        ? != ( forward second ) 508 { = failures + failures 1 } {}
        : Owned third ( make )
        ? != ( distant third ) 508 { = failures + failures 1 } {}
        ? != ( maybe_take ( make ) T ) 508 { = failures + failures 1 } {}
        ? != ( maybe_take ( make ) F ) 0 { = failures + failures 1 } {}
        : Owned borrowed ( make )
        ? != ( inspect borrowed ) 503 { = failures + failures 1 } {}
        ? != ( inspect borrowed ) 503 { = failures + failures 1 } {}
        ? != ( take borrowed ) 508 { = failures + failures 1 } {}
        : ~ Owned mutable ( make )
        ? != ( read_inout mutable ) 503 { = failures + failures 1 } {}
        ? != ( take mutable ) 508 { = failures + failures 1 } {}
        ? != ( take ( identity ( make ) ) ) 508 { = failures + failures 1 } {}
        ? != ( take ( fall_identity ( make ) ) ) 508 { = failures + failures 1 } {}
        : Owned generic ( make )
        ? != ( generic_pass [Owned] generic ) 508 { = failures + failures 1 } {}
        ? != ( take ( make ) ) 508 { = failures + failures 1 } {}
        ? != ( choose T ) 508 { = failures + failures 1 } {}
        ? != ( choose F ) 0 { = failures + failures 1 } {}
        ?? ( failure ) { F error → { ( release error ) } T _ → {} }
        ( release @ Owned { OwnedEmpty } )
        = k + k 1
    }
    ( nurl_println_int failures )
    ^ failures
}

// Deliberately after their callers, including two inference hops and a
// non-consuming control. The false branch still owns its transferred value.
@ distant Owned error → i { ^ ( forward error ) }

@ forward Owned error → i { ^ ( take error ) }

@ maybe_take Owned error b handoff → i { ? handoff { ^ ( take error ) } {} ^ 0 }

@ inspect Owned error → i { ?? error { OwnedLive detail → ^ . detail code OwnedEmpty → ^ 0 } }

@ generic_pass [A] A error → i { ^ ( take error ) }
