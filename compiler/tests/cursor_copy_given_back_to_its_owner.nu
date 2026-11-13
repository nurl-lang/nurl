// cursor_copy_given_back_to_its_owner.nu — a `: ~` cursor copy of an owner
// whose fields were given values of its own, given back to that owner
// (Agora #450, part I).
//
// `: ~ P q o` makes q a cursor over o; `= . q name …` gives q a field of
// its own and keeps o's old name aside. Given back — `= o q`, or a call
// that hands q back — o keeps its value on the runs q still holds it: the
// value q's field replaced is dropped and the field is o's. Taken for
// another value, o's old value was dropped under the field q still shares
// (key field replaced: use after free), or kept while q dropped its field
// again (another field: double free).

$ `stdlib/core/string.nu`

: P { String name String extra }

@ mk s t → String { ^ ( string_from ( nurl_str_cat t `, long enough for a heap buffer` ) ) }

@ ppick P a P b i k → P { ? == k 1 { ^ a } {} ^ b }

@ qid P a → P { ^ a }

@ show s tag P o → v { ( nurl_println ( nurl_str_cat4 tag `: ` ( string_data . o name ) ( nurl_str_cat ` / ` ( string_data . o extra ) ) ) ) }

@ key → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q name ( mk `q name` ) = o q ( show `key` o ) }

@ other → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q extra ( mk `q extra` ) = o q ( show `other` o ) }

@ pick → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q extra ( mk `q extra` ) = o ( ppick o q 0 ) ( show `pick` o ) }

@ ident → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q name ( mk `q name` ) = o ( qid q ) ( show `ident` o ) }

@ arms i c → v {
    : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) }
    : ~ P q o
    ? == c 1 { = . q name ( mk `q name` ) } {}
    ? == c 2 { = . q extra ( mk `q extra` ) } {}
    = o q
    ( show ( nurl_str_cat `arms ` ( nurl_str_int c ) ) o )
}
// q given a whole value of its own first: o is given that value.
@ own → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q name ( mk `q name` ) = q @ P { ( mk `own name` ) ( mk `own extra` ) } = o q ( show `own` o ) }

// A cursor over the cursor: both stand for o's value.
@ chain → v {
    : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) }
    : ~ P q o
    : ~ P q2 q
    = . q2 name ( mk `q2 name` )
    = o q2
    ( show `chain` o )
}

@ main → i {
    ( key ) ( other ) ( pick ) ( ident )
    ( arms 0 ) ( arms 1 ) ( arms 2 )
    ( own )
    ( chain )
    ^ 0
}
