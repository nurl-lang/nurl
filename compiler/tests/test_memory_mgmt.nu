// Test memory management infrastructure
@ main → i {
    ( nurl_print `Testing memory management...\n` )

    // Manually test the reference counting infrastructure by creating a simple closure
    : ( @ i ) simple_func \ i x → i { ^ * x x }

    ( nurl_print `Created simple closure\n` )
    ^ 0
}
