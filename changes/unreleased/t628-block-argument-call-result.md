### Fixed

- **A value block passed as an argument releases the result of the call it ends in** (Agora #628). `( string_len { : String s … ( string_concat s s ) } )` never released the concatenation (a leak once per run of the statement; also with the block nested in another call's argument). The argument is now the call's result for what the caller releases after the call, as `( string_len ( string_concat s s ) )` is.

### Changed

- **A view of a value-block argument that ends in a call cannot be kept past the call** (Agora #628). `: s d ( string_data { ( pick x y ) } )` is now refused as `: s d ( string_data ( pick x y ) )` already was: the block's value is a temporary of the statement wherever the call it ends in may make its result. Bind the block's value first (`: String t { ( pick x y ) }`) and take the view of the binding.
