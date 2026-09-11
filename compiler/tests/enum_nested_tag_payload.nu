// Tag-only enums use the same scalar payload representation for literals,
// variables and call results, in every payload slot.
$ `stdlib/core/io.nu`

: | Level { Low Middle High }
: | Packet { Five Level Level Level Level Level }
: Record { s label i number }
: | Number { NumberValue i }
: | Mixed { Parts Level Record Number }

@ level → Level { ^ High }

@ wrap Level x → Packet { ^ @ Packet { Five Middle x ( level ) @ Level { Low } High } }

@ verify Packet p → i {
    ?? p { Five a b c d e → {
            ? & & & & == a Middle == b High == c High == d Low == e High { ^ 0 } {}
            ^ 1
        } }
}

@ mixed → Mixed { ^ @ Mixed { Parts High @ Record { `record` 37 } @ Number { NumberValue 91 } } }

@ verify_mixed Mixed value → i {
    ?? value { Parts tag record number → {
            ? != tag High { ^ 1 } {}
            ? != . record number 37 { ^ 1 } {}
            ? == 0 ( nurl_str_eq . record label `record` ) { ^ 1 } {}
            ?? number { NumberValue n → { ^ ? == n 91 0 1 } }
        } }
}

@ main → i {
    : Packet packet ( wrap High )
    : Mixed value ( mixed )
    : i result + ( verify packet ) ( verify_mixed value )
    ( nurl_println_int result )
    ^ result
}
