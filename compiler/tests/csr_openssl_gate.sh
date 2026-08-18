#!/usr/bin/env bash
# compiler/tests/csr_openssl_gate.sh — Gate verifying two-way interoperability
# between pure-NURL PKCS#10 CSR (stdlib/std/csr.nu) and OpenSSL.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d /tmp/nurl-csr-test-XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo "==> Building CSR test tool..."
cat << 'EOF' > "$WORK/tool.nu"
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/ed25519.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/csr.nu`
$ `stdlib/std/args.nu`

@ main → i {
    : ArgParser p ( args_new `csr-tool` `PKCS#10 test tool` )
    ( args_parse_argv p )
    : ( Vec String ) av ( args_positionals p )
    : i argc ( vec_len [String] av )
    ? < argc 1 { ( args_free p ) ^ 1 } {}
    : ?String cmdo ( vec_get [String] av 0 )
    : String cmd ?? cmdo { T s → s F _ → ( string_new ) }

    ? ( string_eq cmd ( string_from `gen-p256` ) ) {
        : ?String out_path_o ( vec_get [String] av 1 )
        : String out_path ?? out_path_o { T s → s F _ → ( string_new ) }
        : !( Vec u ) ParseErr sr ( bytes_from_hex `c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721` )
        : ( Vec u ) scalar ?? sr { T v → v F _ → ( vec_new [u] ) }
        : ( Vec String ) sans ( vec_new [String] )
        ( vec_push [String] sans ( string_from `node1.example.com` ) )
        ( vec_push [String] sans ( string_from `api.internal.local` ) )
        : ( Vec u ) der ( csr_generate_p256 `node1.example.com` sans scalar )
        : String pem ( csr_to_pem der )
        ( write_file ( string_data out_path ) ( string_data pem ) )
        ( string_free pem )
        ( vec_free [u] scalar )
        ( vec_free_with [String] sans \ String s → v { ( string_free s ) } )
        ( args_free p )
        ^ 0
    } {}

    ? ( string_eq cmd ( string_from `gen-ed25519` ) ) {
        : ?String out_path_o ( vec_get [String] av 1 )
        : String out_path ?? out_path_o { T s → s F _ → ( string_new ) }
        : !( Vec u ) ParseErr sr ( bytes_from_hex `9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60` )
        : ( Vec u ) sk ?? sr { T v → v F _ → ( vec_new [u] ) }
        : ( Vec String ) sans ( vec_new [String] )
        ( vec_push [String] sans ( string_from `ed25519-node.example.org` ) )
        : ( Vec u ) der ( csr_generate_ed25519 `ed25519-node.example.org` sans sk )
        : String pem ( csr_to_pem der )
        ( write_file ( string_data out_path ) ( string_data pem ) )
        ( string_free pem )
        ( vec_free [u] sk )
        ( vec_free_with [String] sans \ String s → v { ( string_free s ) } )
        ( args_free p )
        ^ 0
    } {}

    ? ( string_eq cmd ( string_from `verify-csr` ) ) {
        : ?String in_path_o ( vec_get [String] av 1 )
        : String in_path ?? in_path_o { T s → s F _ → ( string_new ) }
        : !String IoErr content_o ( read_file ( string_data in_path ) )
        : String content ?? content_o { T s → s F _ → ( string_new ) }
        : !( Vec u ) ParseErr der_o ( csr_from_pem ( string_data content ) )
        ( string_free content )
        : ( Vec u ) der ?? der_o { T v → v F _ → ( vec_new [u] ) }
        : Csr csr ( csr_parse der )
        ( vec_free [u] der )
        ? ! . csr ok {
            ( csr_free csr )
            ( args_free p )
            ( nurl_print `PARSE_ERR\n` )
            ^ 1
        } {}
        : b v ( csr_verify csr )
        ( csr_free csr )
        ( args_free p )
        ? v { ( nurl_print `VERIFY_OK\n` ) ^ 0 } { ( nurl_print `VERIFY_FAIL\n` ) ^ 1 }
    } {}

    ( args_free p )
    ^ 1
}
EOF

"$REPO_ROOT/nurl.sh" "$WORK/tool.nu" "$WORK/tool"

echo "--> Test 1: OpenSSL verifying NURL-generated ECDSA P-256 CSR..."
"$WORK/tool" gen-p256 "$WORK/csr_p256.pem"
openssl req -in "$WORK/csr_p256.pem" -text -noout -verify 2>&1 | grep -E "verify (OK|success)"
echo "    OpenSSL accepted & verified P-256 CSR signature: OK"

echo "--> Test 2: OpenSSL verifying NURL-generated Ed25519 CSR..."
"$WORK/tool" gen-ed25519 "$WORK/csr_ed.pem"
openssl req -in "$WORK/csr_ed.pem" -text -noout -verify 2>&1 | grep -E "verify (OK|success)"
echo "    OpenSSL accepted & verified Ed25519 CSR signature: OK"

echo "--> Test 3: NURL verifying OpenSSL-generated ECDSA CSR..."
openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/ossl_p256.key"
openssl req -new -key "$WORK/ossl_p256.key" -out "$WORK/ossl_p256.csr" -subj "/CN=openssl-client.test" -addext "subjectAltName=DNS:openssl-client.test,DNS:alt.test"
res=$("$WORK/tool" verify-csr "$WORK/ossl_p256.csr")
if [[ "$res" == "VERIFY_OK" ]]; then
    echo "    NURL parsed & verified OpenSSL CSR: OK"
else
    echo "    NURL failed to verify OpenSSL CSR: $res"
    exit 1
fi

echo "--> Test 4: NURL verifying OpenSSL-generated Ed25519 CSR..."
openssl genpkey -algorithm ED25519 -out "$WORK/ossl_ed.key"
openssl req -new -key "$WORK/ossl_ed.key" -out "$WORK/ossl_ed.csr" -subj "/CN=openssl-ed25519.test" -addext "subjectAltName=DNS:ed.test"
res=$("$WORK/tool" verify-csr "$WORK/ossl_ed.csr")
if [[ "$res" == "VERIFY_OK" ]]; then
    echo "    NURL parsed & verified OpenSSL Ed25519 CSR: OK"
else
    echo "    NURL failed to verify OpenSSL Ed25519 CSR: $res"
    exit 1
fi

echo "=========================================="
echo "  ALL CSR OPENSSL INTEROP TESTS PASSED!   "
echo "=========================================="
