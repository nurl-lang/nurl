// result_errors_told_apart_by_their_error_payload: agora #459 — `: !String String x ( px a k ) : ~ !String String y x ? c { = y a } {} ^ y`, px handing back a fresh error and y re-pointed to the parameter's error
// Closed: a result is keyed by its active side — its error's identity when it holds one (mem_ud_ident_key) — and two values are one only where their keys are non-null and their sides agree (__same_value): two errors that own memory are told apart, and the cursor answers "lent" for the caller's (agora #459).
// main: LSan: the fresh error leaked (base 836c0e94).
// map: §7.6 | A2 | runs-clean | - | agora #459: results with an owning error told apart by identity
$ `stdlib/core/string.nu`

@ px ! String String a i k → !String String { ? == k 0 { ^ a } {} ^ @ !String String { F ( string_from `a fresh error long enough for the heap here` ) } }

@ show ! String String r → v { ?? r { T s → { ( nurl_println ( string_data s ) ) } F e → { ( nurl_println ( string_data e ) ) } } }

@ fw ! String String a i k b c → !String String { : !String String x ( px a k ) : ~ ! String String y x ? c { = y a } {} ^ y }

@ main → i {
    : !String String o @ !String String { F ( string_from `the owner error long enough for the heap` ) }
    : !String String p ( fw ( px o 0 ) 1 T )
    : !String String q ( fw ( px o 0 ) 1 F )
    : !String String r ( fw ( px o 0 ) 0 T )
    ( show p ) ( show q ) ( show r ) ( show o )
    ^ 0
}
