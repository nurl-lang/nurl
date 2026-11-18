### Fixed

- **A `~` loop over an Rc payload of numbers ends when the payload is cleared and shrunk through another handle** (AGORA-774, the loop shapes). `~ x pl { ( wipe r ) }`, with `pl` the payload of `r2` and `wipe` clearing and shrinking it through `r` (a clone of `r2`), read freed memory on the next round. That is refused now; a call that only reads through the other handle is still accepted.
