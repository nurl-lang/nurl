// per_call_lender_forwarded_through_ten_functions: `@ f0 String p b c → String { ^ ? c p ( mk ) }` (lent or fresh per call) handed back through ten forwarders
// Closed: the per-call answer is followed at any depth: the fresh result is released, the lent one is not (agora #721).
// main 3b63ee3b: accepted — and leaked: the fresh result was taken for lent.
// map: §2.8 | A2 | runs-clean | - | agora #721: a per-call lender forwarded through ten functions releases its fresh result
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ f0 String p b c → String { ^ ? c p ( mk ) }

@ f1 String p b c → String { ^ ( f0 p c ) }

@ f2 String p b c → String { ^ ( f1 p c ) }

@ f3 String p b c → String { ^ ( f2 p c ) }

@ f4 String p b c → String { ^ ( f3 p c ) }

@ f5 String p b c → String { ^ ( f4 p c ) }

@ f6 String p b c → String { ^ ( f5 p c ) }

@ f7 String p b c → String { ^ ( f6 p c ) }

@ f8 String p b c → String { ^ ( f7 p c ) }

@ f9 String p b c → String { ^ ( f8 p c ) }

@ f10 String p b c → String { ^ ( f9 p c ) }

@ main → i {
    : String p ( mk )
    : String r ( f10 p F )
    : String q ( f10 p T )
    ( nurl_println_int + + ( string_len r ) ( string_len q ) ( string_len p ) )
    ^ 0
}
