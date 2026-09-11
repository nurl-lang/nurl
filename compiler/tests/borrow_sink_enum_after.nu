// A sink consumes the boxed enum; the caller cannot read it afterwards.
$ `stdlib/core/string.nu`

: Payload { String text i number }
: | Value { Item Payload }

@ consume sink Value value → v {}

@ main → i {
    : Value value @ Value { Item @ Payload { ( string_from `owned` ) 7 } }
    ( consume value )
    ?? value { Item payload → { ^ . payload number } }
}
