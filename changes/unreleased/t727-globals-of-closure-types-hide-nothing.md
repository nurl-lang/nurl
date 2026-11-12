### Fixed

- **A global whose type is a closure type or names a trait object no longer hides the declaration below it** (Agora #727). `: ~ ( @ i i ) h 0` or `: ~ ( @ i %Show ) g 0` followed by `@ later i x → i { … }` refused every call to `later` above the global ("call to unknown function 'later'", or "duplicate function '@ i'"): the signature pass took the `@` of the closure type for a function declaration, and the type-name pass took the `%` of `%Show` for a trait or impl header and stepped over the next block. The pre-passes read a global's type whole now.
