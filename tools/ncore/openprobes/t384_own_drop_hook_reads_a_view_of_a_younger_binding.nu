// map: §7.6 | A2 | rejected | - | agora #384: a program's own `H_drop` hook reads a view field whose source is declared after the holder
$ `stdlib/core/string.nu`

: H { s v }

@ H_drop sink H h → v { ( nurl_println . h v ) }

@ main → i {
    : ~ H h @ H { `literal` }
    : String b ( string_from `a string younger than the holder, freed before its hook runs` )
    = h @ H { ( string_data b ) }
    ^ 0
}
