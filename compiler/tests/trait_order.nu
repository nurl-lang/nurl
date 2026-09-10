// Both impls precede the trait. Defaults must be registered before main,
// including distinct associated return/argument types and generic dispatch.
: IntReading { i value }
: FloatReading { f value }

% Reading IntReading {
    type Elem i
    @ read IntReading self → i { ^ . self value }
}

% Reading FloatReading {
    type Elem f
    @ read FloatReading self → f { ^ . self value }
    @ twice FloatReading self f fallback → f { ^ + . self value fallback }
}

@ measure [A : Reading] A self → i { ^ # i ( read self ) }

@ main → i {
    : IntReading a @ IntReading { 21 }
    : FloatReading z @ FloatReading { 2.5 }
    ( nurl_println_int ( twice a 0 ) )
    ( nurl_println_int # i * ( twice z 1.5 ) 10.0 )
    ( nurl_println_int ( measure [IntReading] a ) )
    ^ 0
}

% Reading [T] {
    type Elem
    @ read T self → Elem
    @ twice T self Elem fallback → Elem { ^ + ( read self ) ( read self ) }
}
