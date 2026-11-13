// enum_payload_handed_back_under_a_mutable_alias_runs_clean: `?? e { EA s → { : ~ String t s ? == k 0 { = t ( string_from … ) } {} ^ t } … }` over a local enum a call made — t is the payload on one path, a value of its own on the other.
// Agora #814 item 1: `^ t` was answered lent out of the local enum (heap-use-after-free). A `: ~` alias of a payload (`__etake_ofm`) is copied, never taken: where the enum keeps the payload, or where t owns a value of its own (its flag).
// map: §2.8 | A2 | runs-clean | - | agora #814: a payload handed back under a `: ~` alias is copied
$ `stdlib/core/string.nu`

: | E { EA String EB i }

@ mke s t → E { ^ @ E { EA ( string_from t ) } }

@ f i k → String {
    : E e ( mke `a payload string long enough for the heap` )
    ?? e { EA s → { : ~ String t s ? == k 0 { = t ( string_from `a re-pointed value, long enough heap` ) } {} ^ t } EB j → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String r ( f 1 )
    ( nurl_println ( string_data r ) )
    : String r2 ( f 0 )
    ( nurl_println ( string_data r2 ) )
    ^ 0
}
