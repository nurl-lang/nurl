// join_bound_copy_given_back_to_its_owner_runs_clean: `: ~ P q ? c o r`, a field of q replaced (the key or another), then `= o q` or `= o ( ppick o q 0 )`; both runs.
// Closed (agora #819): on the run q holds o's value — its key with the replaced fields put back is o's — o keeps it, what q's field replaced goes, the field is o's (mem_ff_write_back, __ff_orig_value).
// main 160339c1: heap-use-after-free on the run q holds o's value.
// map: §7.6 | A2 | runs-clean | - | agora #819: a join-bound binding with a replaced field given back to its owner
$ `stdlib/core/string.nu`

: P { String name String extra }

@ mk s t → String { ^ ( string_from ( nurl_str_cat t `, long enough for a heap buffer` ) ) }

@ ppick P a P b i k → P { ? == k 1 { ^ a } {} ^ b }

@ show s tag P o → v { ( nurl_println ( nurl_str_cat4 tag `: ` ( string_data . o name ) ( nurl_str_cat ` / ` ( string_data . o extra ) ) ) ) }

@ key i c → v {
    : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) }
    : ~ P r @ P { ( mk `r name` ) ( mk `r extra` ) }
    : ~ P q ? == c 1 o r
    = . q name ( mk `q name` )
    = o q
    ( show ( nurl_str_cat `key ` ( nurl_str_int c ) ) o )
}

@ other i c → v {
    : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) }
    : ~ P r @ P { ( mk `r name` ) ( mk `r extra` ) }
    : ~ P q ? == c 1 o r
    = . q extra ( mk `q extra` )
    = o q
    ( show ( nurl_str_cat `other ` ( nurl_str_int c ) ) o )
}

@ call i c → v {
    : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) }
    : ~ P r @ P { ( mk `r name` ) ( mk `r extra` ) }
    : ~ P q ? == c 1 o r
    = . q name ( mk `q name` )
    = o ( ppick o q 0 )
    ( show ( nurl_str_cat `call ` ( nurl_str_int c ) ) o )
}

@ main → i {
    ( key 0 ) ( key 1 )
    ( other 0 ) ( other 1 )
    ( call 0 ) ( call 1 )
    ^ 0
}
