### Fixed

- **A name bound in a `;` defer body no longer takes over an outer binding's name** (Agora #636). `: i a 5`, `; { : i a … }`, `^ a` returned uninitialised stack memory, and with a closure or a String of that name the later use called or read through storage the defer had not written yet (a crash). A defer body bound its names in the enclosing scope, so after the `;` the name meant the body's binding. A defer body's names are now its own, as an arm's are.

### Changed

- **A name bound in a `;` defer body cannot be used after the body** (Agora #636). `; { : i a 7 … }` then `a` is "use of undefined identifier 'a'" where no outer `a` exists; it used to compile and read the body's storage, which is written only when the defer runs. What a defer body binds is still released after the whole defer chain has run, so a defer registered inside the body, or an older defer reading a holder the body pointed at one of its locals, still finds it.
