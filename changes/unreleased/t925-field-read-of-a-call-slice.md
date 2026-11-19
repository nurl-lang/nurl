### Fixed

- **A slice a call made, read for one field, is released** (AGORA-925). `( n . ( mk ) 1 )`, `. ( mk ) length` and `. ( mk ) k`, where `mk` returns a slice, read the field and then released the slice nowhere, so it leaked. The same happened for a closure that makes a slice. The slice is now released after the read on the runs the call says it is the caller's. A String element read out of it is a copy of its own, and a slice the call lent stays its owner's.
