// tools/fuzz/parse_harness.nu — a single dispatch harness for fuzzing the
// untrusted-input parsers. Usage: `parse_harness <which> <file>`.
//
// It reads `file` (raw bytes for binary formats, a C-string for text
// formats), feeds it to the selected parser, and frees whatever came back.
// The ONLY acceptable outcomes are a parsed value or a graceful parse error
// — never a crash, out-of-bounds access, UB, or a hang. Built with
// ASan+UBSan and driven over mutated inputs by fuzz_parsers.sh, any
// sanitizer report or non-zero exit is a real parser bug.
//
// which ∈ { x509 cbor msgpack json yaml xml toml }

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/yaml.nu`
$ `stdlib/ext/xml.nu`
$ `stdlib/ext/toml.nu`
$ `stdlib/ext/cbor.nu`
$ `stdlib/ext/msgpack.nu`
$ `stdlib/std/x509.nu`

@ __fuzz_bytes s path → ( Vec u ) {
    : !( Vec u ) IoErr rb ( read_file_bytes path )
    ^ ?? rb { T b → b F _ → ( vec_new [u] ) }
}

@ main → i {
    ? < ( nurl_argc ) 3 {
        ( nurl_eprintln `usage: parse_harness <x509|cbor|msgpack|json|yaml|xml|toml> <file>` )
        ^ 2
    } {}
    : s which ( nurl_argv 1 )
    : s path ( nurl_argv 2 )

    // ── binary formats (raw bytes) ──────────────────────────────────
    ? != 0 ( nurl_str_eq which `x509` ) {
        : ( Vec u ) b ( __fuzz_bytes path )
        : X509 c ( x509_parse b )
        ( x509_free c )
        ( vec_free [u] b )
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `cbor` ) {
        : ( Vec u ) b ( __fuzz_bytes path )
        : !Json CborErr r ( cbor_decode b )
        ?? r { T j → ( json_free j ) F _ → {} }
        ( vec_free [u] b )
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `msgpack` ) {
        : ( Vec u ) b ( __fuzz_bytes path )
        : !Json MsgpackErr r ( msgpack_decode b )
        ?? r { T j → ( json_free j ) F _ → {} }
        ( vec_free [u] b )
        ^ 0
    } {}

    // ── text formats (C-string; embedded NUL truncates, by contract) ─
    ? != 0 ( nurl_str_eq which `json` ) {
        : s src ( nurl_read_file path )
        : !Json JsonError r ( json_parse src )
        ?? r { T j → ( json_free j ) F _ → {} }
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `yaml` ) {
        : s src ( nurl_read_file path )
        : !Json YamlErr r ( yaml_parse src )
        ?? r { T j → ( json_free j ) F _ → {} }
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `xml` ) {
        : s src ( nurl_read_file path )
        : !Xml XmlErr r ( xml_parse src )
        ?? r { T x → ( xml_free x ) F _ → {} }
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `toml` ) {
        : s src ( nurl_read_file path )
        : !TomlValue TomlErr r ( toml_parse src )
        ?? r { T t → ( toml_value_free t ) F _ → {} }
        ^ 0
    } {}

    ( nurl_eprintln ( nurl_str_cat `unknown parser: ` which ) )
    ^ 2
}
