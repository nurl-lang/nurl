### Fixed

- **A typed `:` binding of a value block whose tail views the block's own local gets a copy** (AGORA-953). `: s e { : String x … ( string_data x ) }` and `: ~ s e { … }`, with the type written, now take the same copy rule as the inferred `: e { … }`. They used to read freed memory once handed back. No source changes.
