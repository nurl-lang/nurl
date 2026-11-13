### Fixed

- **A value block whose tail is named like the binding it initialises hands that tail over** (Agora #823). `: String s { : String s ( string_from … ) s }  ( eat s )` was a heap-use-after-free: the block-local kept its drop while the sink took the value. The same was true for a Vec, a struct with its own `% Drop`, a `: ~` spelling, a return, and a nested block. The tail now moves by its slot, as `= s { : String s … s }` does since #806.
