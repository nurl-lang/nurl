// fixture: module; The importing program supplies Reading AFTER importing this module.
: IntReading { i value }
: FloatReading { f value }

% Reading IntReading {
    type Elem i
    @ read IntReading self → i { ^ . self value }
}

% Reading FloatReading {
    type Elem f
    @ read FloatReading self → f { ^ . self value }
}
