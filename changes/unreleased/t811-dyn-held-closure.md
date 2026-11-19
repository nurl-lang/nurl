### Fixed

- **A `dyn` object built of a struct that holds a closure now carries that closure's effects** (AGORA-811). In `( dyn Runner @ C { \ → v { ( vec_clear … ( rc_get … r ) ) } } )`, a method that runs the field closure cleared an Rc payload that a view through another handle went on reading. That is refused now, as it was for the struct passed directly.
