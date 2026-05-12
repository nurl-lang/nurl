// test_drop.nu
// Test: User Drop trait implementation.

: Dropper {
    i id
}

% Drop Dropper {
    @ drop Dropper d → v {
        ( nurl_print `Dropping id: ` )
        ( nurl_print ( nurl_str_int . d id ) )
        ( nurl_print `\n` )
    }
}

@ get_dropper i id → Dropper {
    : Dropper d @ Dropper { id }
    ( nurl_print `About to return from get_dropper\n` )
    ^ d
}

@ main → i {
    ( nurl_print `Start main\n` )
    
    // 1. Simple block drop
    {
        : Dropper d1 @ Dropper { 1 }
        ( nurl_print `Inside simple block\n` )
    }
    
    // 2. Arm-local drop
    ? 1 {
        : Dropper d2 @ Dropper { 2 }
        ( nurl_print `Inside then-arm\n` )
    } {
        ( nurl_print `Inside else-arm\n` )
    }
    
    // 3. Escape from arm
    : Dropper d3 ? 1 {
        ( nurl_print `Escaping from then-arm\n` )
        @ Dropper { 3 }
    } {
        @ Dropper { 0 }
    }
    
    // 4. Return from function
    : Dropper d4 ( get_dropper 4 )
    
    ( nurl_print `End main\n` )
    ^ 0
}
