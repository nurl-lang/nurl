@ is_even i n → b { ? == n 0 { ^ T } {} ^ ( is_odd - n 1 ) }
@ is_odd i n → b { ? == n 0 { ^ F } {} ^ ( is_even - n 1 ) }
@ main → i { ? ( is_even 10 ) { ^ 1 } { ^ 0 } }
