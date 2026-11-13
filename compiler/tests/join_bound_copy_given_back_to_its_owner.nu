// join_bound_copy_given_back_to_its_owner.nu — a `: ~` binding of a join of
// two owners (`: ~ P q ? c o r`), given a field of its own, then given back
// to one of them (Agora #819).
//
// q holds o's value on one run and r's on the other; a field stored through
// it is its own, and what it replaced stays its source's. Given back to o,
// on the run q holds o's value — its own key, the fields it replaced put
// back, is o's — o keeps that value, what q's field replaced goes, and the
// field is o's. On the other run o is given r's value as a lend, as before.
// Before, o's old value was dropped whole under the field q still shared
// with it (use after free).

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
