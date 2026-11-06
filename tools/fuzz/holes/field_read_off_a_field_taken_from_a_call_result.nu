// field_read_off_a_field_taken_from_a_call_result: agora #474 — a field read two or more levels deep straight off a call's struct result (`. . ( boxit … ) v b`, `: String s . . ( boxit … ) v a`, `( string_len . . ( boxit … ) v a )`, `^ . . ( … ) v a`, `. . . ( box2 k ) w v b`, `: Pair p . . ( box2 k ) w v`). The inner read took its field out of the temporary (h266) and published it as owned, but the outer read only treated a call's result as a temporary: the taken struct, and the String it owns, were owned by nothing.
// Closed: a field read whose object is a field the read inside it took out of a call's result treats that object as the temporary it is, owned exactly when the inner read's flag holds: the rest is dropped where it is read, an owning field leaves as a value of its own (gen_member, __mb_tmp_flag).
// main (before this PR): LeakSanitizer, one Pair's String per round of every shape.
// map: §7.1 | A2 | runs-clean | - | agora #474: a field read off a field taken from a call's struct result; the taken struct was never dropped (leak)
$ `stdlib/core/string.nu`

: Pair { String a i b }
: Box1 { Pair v }
: Box2 { Box1 w }

@ boxit Pair p → Box1 { ^ @ Box1 { p } }

@ mkpair i k → Pair { ^ @ Pair { ( string_from `a string long enough to be on the heap, and then some more bytes` ) k } }

@ box2 i k → Box2 { ^ @ Box2 { ( boxit ( mkpair k ) ) } }

@ geta i k → String { ^ . . ( boxit ( mkpair k ) ) v a }

@ once i k → i {
    : i n . . ( boxit ( mkpair k ) ) v b
    : String s . . ( boxit ( mkpair k ) ) v a
    : i c ( string_len . . ( boxit ( mkpair k ) ) v a )
    : String r ( geta k )
    : i d . . . ( box2 k ) w v b
    : String s3 . . . ( box2 k ) w v a
    : Pair p . . ( box2 k ) w v
    ^ + + + + + + n ( string_len s ) c ( string_len r ) d ( string_len s3 ) + ( string_len . p a ) . p b
}

@ main → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 10 { = t + t ( once k ) = k + k 1 }
    ( nurl_println_int t )
    ^ 0
}
