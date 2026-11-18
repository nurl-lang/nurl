### Fixed

- **Storing a `: ~` cursor of a `??` payload now moves the option, as storing the payload by name does** (AGORA-840). In `?? o { T x → { : ~ cur x  : H q @ H { cur 0 } } }`, the literal takes `o`'s payload, so reading `o` afterwards read freed memory. That read is refused now, also through a cursor of a cursor and for a `?String`. Storing a copy, `( mem_dup cur )`, still leaves `o` alone. One shape stays open: a join cursor pushed into a Vec leaks.
