// Test memory management infrastructure
@ main → i {
    ( nurl_print `Testing memory management...\n` )

    // Manually test the reference counting infrastructure by creating a simple closure
    // The closure takes one 'i' parameter, so the declared type must say
    // so — ': ( @ i )' declared a ZERO-param closure and the compiler now
    // rejects binding a differently-shaped closure to it (any later
    // invoke through the declared type would reinterpret its arguments).
    : ( @ i i ) simple_func \ i x → i { ^ * x x }

    ( nurl_print `Created simple closure\n` )
    ^ 0
}
