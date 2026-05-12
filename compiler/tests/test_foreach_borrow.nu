// test_foreach_borrow.nu
// Test: Ownership of elements in foreach loop (Borrow).

: Dropper {
    i id
}

% Drop Dropper {
    @ drop Dropper d → v {
        ( nurl_print `Dropping inner id: ` )
        ( nurl_print ( nurl_str_int . d id ) )
        ( nurl_print `\n` )
    }
}

@ main → i {
    : [ i nums [ i | 10 20 30 ]
    
    ( nurl_print `Start foreach\n` )
    ~ n nums {
        ( nurl_print `Processing: ` )
        ( nurl_print ( nurl_str_int n ) )
        ( nurl_print `\n` )
        
        // Luodaan omistettu Dropper lohkon sisällä - TÄMÄ pitäisi dropata joka kierroksella
        : Dropper inner @ Dropper { n }
    }
    ( nurl_print `End foreach\n` )
    
    ^ 0
}
