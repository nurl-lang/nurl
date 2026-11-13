### Fixed

- **A closure handed out through a value block is checked as the bare closure is** (Agora #638). `^ { : String s … : ( @ i i ) f \ … s … f }` returned a closure over a String the function released (heap-use-after-free). It is now refused with the message `^ f` gets. `= a { : i z ( a 1 ) a }`, a closure given a block ending in itself, released a's env and stored it back; it is now `= a a`.
- **A closure bound from a value block carries what its tail binding captured** (Agora #835 item 1b). `: g { : String s … : ( @ i i ) f \ … s … f }  ^ g` handed out a closure over a released String; it is now refused as `: g f  ^ g` is.
