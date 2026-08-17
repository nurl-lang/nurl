# pqc

Post-quantum key encapsulation on the command line, and a probe for
whether the servers you talk to are ready for it.

`pqc` implements **ML-KEM** — the key-encapsulation mechanism NIST
standardised as [FIPS 203][fips203] in August 2024, previously known as
CRYSTALS-Kyber — at all three parameter sets, in pure NURL. No
libcrypto, no liboqs, no `-loqs`: this links libc and nothing else.

[fips203]: https://csrc.nist.gov/pubs/fips/203/final

## Why you'd want it

Two reasons, and the second is the one that earns a place on a laptop.

**A KEM you can actually run.** Generate a key pair, encapsulate to it,
decapsulate — the primitive that hybrid TLS, Signal's PQXDH and every
"harvest now, decrypt later" mitigation is built on.

**A post-quantum readiness check.** `pqc probe HOST` completes a real
TLS 1.3 handshake and reports which key-exchange group the server
actually chose:

```console
$ pqc probe cloudflare.com www.google.com github.com www.wikipedia.org
host                              PQ?  group
cloudflare.com                    PQ   X25519MLKEM768
www.google.com                    PQ   X25519MLKEM768
github.com                        no   x25519
www.wikipedia.org                 PQ   X25519MLKEM768
```

That distinction is easy to lose. Offering the hybrid group is not the
same as getting it: a server that has not deployed ML-KEM falls back to
X25519 silently, the handshake succeeds, and nothing anywhere says so.
Traffic to that server is recordable today and decryptable by a
sufficiently large quantum computer later. `pqc probe` is the answer to
"did the upgrade actually take?"

It exits `0` only when every host named negotiated a post-quantum
group, `1` when one of them fell back, and `2` when a handshake failed
outright — so it drops straight into a deployment check:

```sh
pqc probe api.example.com || echo "not post-quantum yet"
```

## Usage

```
pqc keygen [-l 768] -o NAME    write NAME.ek and NAME.dk
pqc encaps NAME.ek [-o CT]     encapsulate; prints the shared secret
pqc decaps NAME.dk CT          recover the same shared secret
pqc probe HOST...              report each server's key-exchange group
pqc bench [-l 768] [-n N]      operations per second on this machine
pqc kat                        self-test against NIST's ACVP vectors
```

Parameter sets are `-l 512`, `-l 768` (the default) and `-l 1024`,
targeting roughly the security of AES-128, AES-192 and AES-256. For
`encaps` and `decaps` the level is inferred from the key's length — the
three sizes are distinct, so you never have to remember which set a key
came from.

```console
$ pqc keygen -o demo
encapsulation key -> demo.ek (1184 bytes)
decapsulation key -> demo.dk (2400 bytes)

$ pqc encaps demo.ek -o demo.ct
ML-KEM-768
ciphertext -> demo.ct (1088 bytes)
shared secret 08c07245e811541506dfd489b50ed5c1b001808933d09e3b21012e9d1fd248df

$ pqc decaps demo.dk demo.ct
ML-KEM-768
shared secret 08c07245e811541506dfd489b50ed5c1b001808933d09e3b21012e9d1fd248df
```

## Sizes and speed

| set | ek | dk | ciphertext | shared secret |
|---|---|---|---|---|
| ML-KEM-512 | 800 | 1632 | 768 | 32 |
| ML-KEM-768 | 1184 | 2400 | 1088 | 32 |
| ML-KEM-1024 | 1568 | 3168 | 1568 | 32 |

Measured with `pqc bench -n 500` on one core of an x86-64 desktop:

```
ML-KEM-768  500 iterations
  keygen  15756 op/s
  encaps  16073 op/s
  decaps  13802 op/s
```

Roughly 60–70 µs per operation — fast enough that adding it to a TLS
handshake costs less than the handshake's own round trip.

## Correctness

`pqc kat` runs a built-in subset of NIST's vectors. The full check lives
in the compiler repository:

- `compiler/tests/mlkem_vectors.nu` — an offline subset that runs on
  every build, plus a round trip and the implicit-rejection path at each
  parameter set.
- `tools/mlkem_acvp_gate.sh` — every published ACVP case, 180 of them,
  fetched from `usnistgov/ACVP-Server` and compared byte for byte.

A KEM cannot be validated by round-tripping itself: encapsulate and
decapsulate with the same broken implementation and the shared secrets
still agree. The vectors are the only real oracle, and the gate has been
mutation-tested — a wrong twiddle factor, a dropped NTT layer, a swapped
noise sign and an unconditional implicit-rejection select are each
caught.

## Hybrid TLS

The NURL standard library's TLS 1.3 client offers `X25519MLKEM768`
(group `0x11ec`) as its first preference, so ordinary `tls_connect`
calls get post-quantum key exchange wherever the server supports it. The
shared secret is `ML-KEM secret ‖ X25519 secret`, which means the
session survives *either* primitive being broken — you are never worse
off than plain X25519.

```nurl
: !*TlsConn TlsErr r ( tls_connect `cloudflare.com` 443 `cloudflare.com` )
?? r {
    T c → {
        ? ( tls_is_post_quantum c ) { ... } {}
    }
    F e → { ... }
}
```

## Licence

MIT OR Apache-2.0
