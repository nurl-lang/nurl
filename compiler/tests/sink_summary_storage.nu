// Parameter implications are copied into the summary table. The compiler
// must release the temporary record after that copy, including forward calls.
@ relay i value → v { ( output value ) }

@ output i value → v { ( nurl_println_int value ) }

@ main → i { ( relay 7 ) ^ 0 }
