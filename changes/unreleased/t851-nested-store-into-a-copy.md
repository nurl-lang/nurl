### Fixed

- **An owning value stored through a nested field path into a loop element, a by-value parameter or a by-value capture is refused, as a one-level store is** (AGORA-851). `~ p os { = . . p inner name ( string_from … ) }` landed in the loop's copy and leaked the new String. A capturing closure stored into a loop element's field leaked its environment and was warned only as a lost write. Both are refused now, with the same message as `= . p name …`. A closure that captures nothing, and a nested scalar store into such a copy, are warned as lost.
