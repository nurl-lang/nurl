### Fixed

- **An enum whose payload cannot be copied is dropped in a function above its declaration** (Agora #752). With `: | E { EA R EB i }` (R with its own `% Drop`) declared below `@ f1 i k → i { : E e ( mke k ) … }`, e was never dropped — nor an E handed to a `sink` parameter, nor the old value of `= e …` — because the enum's compiler drop was known only once its declaration was compiled. It is registered with the type layouts now, before any function body, as a copyable enum's already was (Agora #744); each destructor runs once.
