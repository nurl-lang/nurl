// A closure whose body makes and calls a closure over its own parameter.
@ main → i {
    : ( @ i i ) outer \ i x → i {
        : ( @ i i ) inner \ i y → i { ^ + x y }
        ^ ( inner 1 )
    }
    ^ ( outer 2 )
}
