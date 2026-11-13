// panic_in_drop_beside_a_taken_result.nu — a function hands back a value
// it copied or took out of what held it — a local struct's field
// (`^ . h name`), a payload of a local enum (`^ s`), a copy out of a
// call-made enum — while a local's destructor panics on the way out
// (Agora #814, #677 D). The value is no binding's any more and not the
// caller's yet: it is journaled for that window, and the panic's unwind
// drops it once. Before, it leaked under recover. A field of a borrowed
// parameter and a borrowed enum's payload stay the caller's; a run with no
// panic hands the value over as before.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ? == . b boom 1 { ( panic `boom` ) } {} } }

: Holder { String name i n }
: | E { EA String EB i }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

@ mke s t → E { ^ @ E { EA ( string_from t ) } }

@ pfield Holder h → String { : Bomb loc ( bomb `l` 1 ) ^ . h name }

@ ppay E e → String { : Bomb loc ( bomb `l` 1 ) ?? e { EA s → { ^ s } EB j → {} } ^ ( string_from `none` ) }

@ cpay i k → String { : E e ( mke `a call-made enum payload, long enough heap` ) : Bomb loc ( bomb `l` 1 ) ?? e { EA s → { ^ s } EB j → {} } ^ ( string_from `none` ) }

@ nopanic i k → String { : Holder h @ Holder { ( string_from `a holder name, long enough for heap` ) 1 } : Bomb loc ( bomb `l` 0 ) ^ . h name }

@ run ( @ v ) f → v { : !v PanicInfo r ( recover f ) }

@ main → i {
    : Holder h @ Holder { ( string_from `the caller holder, long enough for heap` ) 1 }
    ( run \ → v { : String r ( pfield h ) } )
    : E e ( mke `the caller enum payload, long enough heap` )
    ( run \ → v { : String r ( ppay e ) } )
    ( run \ → v { : String r ( cpay 1 ) } )
    : String q ( nopanic 1 )
    ( nurl_println ( string_data q ) )
    ( nurl_println ( string_data . h name ) )
    ^ 0
}
