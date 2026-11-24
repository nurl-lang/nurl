$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ pick i k → i {
    : String s ( string_from `a string alive whichever way pick returns` )
    : W w @ W { ( string_data s ) }
    ? == k 0 { ^ 1 } {}
    ^ 0
}

@ main → i { ^ ( pick 0 ) }
