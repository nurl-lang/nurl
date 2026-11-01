### Fixed

- **Two leaks through forwarders are gone** (Agora #375).
  - `= o ( f … )`, with `f` handing back what another function lends and
    defined above its caller, kept `o`'s old value instead of freeing it
    when an argument was a number, a struct field or an alias of a local,
    or when `f` was part of a cycle.
  - A forwarder of a function that hands back a fresh value on some runs
    and a lend on others answered "lent" on every run, so the caller
    never freed the fresh values.
  - `= o ( f e )`, with `e` bound from a function that lends part of `o`
    itself (`: Node e ( kid0 ( optkids o ) )`), freed `o`'s old value
    while `o` went on to hold a piece of it (heap-use-after-free). The
    old value is now kept back there.
