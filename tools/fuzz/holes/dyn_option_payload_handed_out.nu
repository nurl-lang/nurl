// dyn_option_payload_handed_out: agora #185 — the payload of such an option scrutinee handed out of the match (dyn_option_payload_handed_out).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h791 | agora #185: the payload of such an option scrutinee handed out of the match
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick String p b c → String { ^ ? c p ( mk ) }

@ pick_opt String p b c → ?String { ^ @ ?String { T ? c p ( mk ) } }

@ main → i {
    : String p ( mk )
    : String t ?? ( pick_opt p F ) { T s → s F → ( mk ) }
    : String u ?? ( pick_opt p T ) { T s → s F → ( mk ) }
    ( nurl_println_int + + ( string_len t ) ( string_len u ) ( string_len p ) )
    ^ 0
}
