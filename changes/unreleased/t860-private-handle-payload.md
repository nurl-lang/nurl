### Fixed

- A module's public handle over its own private type (`pub : H { ( Shared Impl ) ctl }`, with no `H_drop` of its own) can be copied in another file. The copy died with `private type 'Impl' is not visible across files`, pointing into a pseudo-file `<libh-targ>`, in a file that never named `Impl`. (AGORA-860)
