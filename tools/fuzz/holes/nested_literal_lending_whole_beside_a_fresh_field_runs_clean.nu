// nested_literal_lending_whole_beside_a_fresh_field_runs_clean: `^ @ O2 { @ P1 { . h name } ( string_from … ) }` with h a borrowed parameter — the nested literal lends h's field whole, beside a fresh field of the outer one.
// Agora #783 item 5: the outer literal was answered lent whole and its fresh String leaked; a nested literal that lends whole is copied as a lent field is (#635's rule), where it holds no view.
// map: §7.6 | A2 | runs-clean | - | agora #783: a nested literal lending whole beside a fresh field is copied, the result owns all it holds
$ `stdlib/core/string.nu`

: Holder { String name i n }
: P1 { String a }
: O2 { P1 p String b }

@ f Holder h → O2 { ^ @ O2 { @ P1 { . h name } ( string_from `a fresh field string, long enough for heap` ) } }

@ main → i {
    : Holder h @ Holder { ( string_from `the holder name string, long enough heap` ) 1 }
    : O2 o ( f h )
    ( nurl_println ( string_data . . o p a ) )
    ( nurl_println ( string_data . o b ) )
    ( nurl_println ( string_data . h name ) )
    ^ 0
}
