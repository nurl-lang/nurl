### Fixed

- **A binding given a join over two locals' lends takes over only the one it holds** (AGORA-953). `: e ? c ( id a ) ( id b )  = o e` used to take both `a` and `b` over, so the one the join did not select was never released, a leak. Ownership is now decided by the value's identity at run time. No source changes.
