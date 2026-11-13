### Fixed

- **A trait object holding an `Rc` share is seen by the same-`Rc` rule** (Agora #738). Given `: %Wiper d ( dyn Wiper @ G { r } )` whose method clears or grows the payload of `. g r`, a view of that payload taken through another handle `r2` outlived `( wipe_it d )` (heap-use-after-free). A trait object now reaches the `Rc` types its trait's implementing types reach, and a `dyn` call drops what one of its implementations drops. A trait object whose trait no `Rc`-holding type implements is unaffected.

### Known issues

- The answer is per trait, not per object: an object of an implementation that holds no `Rc`, beside an implementation that holds one, counts as holding it; and a `dyn` call counts as dropping or growing what any implementation does. A view through another handle across such a call is refused even when the object's own type only reads.
