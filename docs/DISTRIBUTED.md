# Distributed computing stack

NURL ships a complete, self-contained stack for running distributed
computation over a **churning, NAT'd, mobile** peer set — laptops and phones
with no public IP and no open inbound ports, roaming between wifi and cellular.
It is built entirely on the standard library (`stdlib/net/*`, `stdlib/dist/*`,
`stdlib/std/lifeguard.nu`) over the pure-POSIX socket layer described in
[`NETWORKING.md`](NETWORKING.md) and the fiber runtime in
[`ASYNC.md`](ASYNC.md). No external frameworks, no OS tunnel
(no Android `VpnService` / iOS `NetworkExtension`) — just userspace UDP/TCP,
symmetric crypto, and gossip.

The whole design follows three invariants:

1. **A peer is a static public key, not an address.** Endpoints move; identity
   does not. Every layer above the wire addresses peers by their X25519 public
   key, and the transport keeps the `pubkey → endpoint` mapping current as
   peers roam.
2. **Reachability is never zero — direct when possible, relayed when not.** A
   pair tries a direct encrypted path (hole-punched UDP); if the NAT topology
   forbids it (symmetric / CGNAT), traffic falls back to a dumb relay. The
   layers above never see the difference.
3. **State is eventually consistent — gossip + CRDTs, never consensus.** No
   Raft, no Paxos. A mesh that re-partitions every time a phone changes cells
   cannot afford a quorum protocol; convergence comes from
   commutative/idempotent merges instead.

---

## The stack at a glance

```
   COMPUTE      job.nu           submit→ring_owner executes→result (keystone)
   (The Crown)  lease.nu         fencing tokens for side-effecting tasks
                identity.nu      stable, never-reused replica ids
                sim.nu           deterministic chaos-simulation harness
   ────────────────────────────────────────────────────────────────
   dist/        ring.nu          consistent-hash key ownership
                crdt.nu          PN-Counter · LWW-Register · OR-Set
                replicator.nu    CRDT codecs + ownership-scoped anti-entropy
   ────────────────────────────────────────────────────────────────
   membership   membership.nu    pubkey-keyed SWIM table (+ self-refutation)
                failuredetector  probe loop: ping / ping-req / suspect
                heartbeat.nu     liveness on a dedicated OS thread
                lifeguard.nu     local-health + scaled suspicion (anti-FP)
   ────────────────────────────────────────────────────────────────
   net/transport.nu   THE SEAM — send(pubkey,msg) / broadcast(group,msg)
                      hides direct-vs-relay, endpoint roaming, path upgrade
   ────────────────────────────────────────────────────────────────
   net/rendezvous.nu  signaling: pubkey → candidates + relay (discovery)
   net/nat.nu         STUN candidates, NAT-type probe, UDP hole punch
   net/stun.nu        RFC 8489 Binding (server-reflexive address)
   net/relay.nu       DERP-style dumb forwarder + group multicast
   ────────────────────────────────────────────────────────────────
   net/securedgram.nu pubkey-addressed encrypted UDP + roaming
                      ├─ net/session.nu   AEAD + sliding replay window
                      └─ net/noise.nu     Noise_IKpsk2 handshake
   ────────────────────────────────────────────────────────────────
   std/udp.nu · std/bytes.nu · ext/crypto.nu       (NETWORKING.md)
```

Read it bottom-up to understand how a datagram is secured and delivered;
top-down to understand how an application addresses a peer. They meet at
**`net/transport.nu`**, the seam every higher layer binds to — and the top of
the stack, **The Crown**, mounts *verifiable distributed computation* onto the
converged-state overlay: work that is submitted, owned, executed, returned,
and proven correct under churn (see [The Crown](#the-crown--from-distributed-state-to-distributed-computation) below).

---

## Phase 0 — secure datagram substrate

### `net/noise.nu` — handshake

A `Noise_IKpsk2_25519_ChaChaPoly_SHA256` handshake over `ext/crypto.nu`
(X25519 / SHA-256 / HKDF / ChaCha20-Poly1305). The **IK** pattern means the
initiator already knows the responder's static key (it came from rendezvous),
so the session opens in one round trip; the **psk2** mesh pre-shared key gates
who may even attempt to join. `noise_split` derives the two directional
transport keys.

`noise_init` · `noise_write_msg1` / `noise_read_msg1` · `noise_write_msg2` /
`noise_read_msg2` · `noise_split` → `NoiseKeys{send, recv}`.

### `net/session.nu` — transport AEAD

Wraps the Noise transport keys in a record layer: a counter nonce per
direction plus a **sliding 64-bit replay window** that accepts re-ordered
datagrams (UDP reorders freely) while rejecting replays, duplicates, and
too-old packets.

`session_new` · `session_seal` → `Sealed{counter, ct}` · `session_open` →
`?(Vec u)`.

### `net/securedgram.nu` — pubkey-addressed encrypted UDP, with roaming

The Phase-0 finale. It ties the handshake and session onto a single UDP socket
behind the only API the layers above ever touch:

```
send_to(pubkey, bytes)        recv() → (pubkey, bytes)
```

Peers are addressed by their **static public key**; the `host:port` endpoint is
mutable. WireGuard-style index-routed framing (`[type][sender_index]…`) maps an
inbound datagram to a session in O(1)-ish. The single most important rule for
mobile stability lives here — **the roaming rule**:

> On every *authenticated* inbound datagram, update the peer's endpoint to the
> packet's source address.

That one line is why a wifi↔cellular switch continues from the next packet
instead of forcing a reconnect.

`securedgram_open` · `securedgram_add_peer` · `securedgram_connect` ·
`securedgram_send` · `securedgram_recv` → `?RecvData{peer_pubkey, data}` ·
`securedgram_rebind` · `securedgram_local_addr` · `securedgram_close`.

---

## Phase 1 — NAT traversal

### `net/stun.nu` — RFC 8489 Binding

A minimal STUN client. Send a Binding request on the **same** UDP socket the
transport uses; the server echoes back the public `host:port` it observed —
your *server-reflexive* candidate. XOR-MAPPED-ADDRESS is de-obfuscated with
NURL's native `^^` (bitwise XOR) operator.

`stun_build_request` · `stun_parse` → `?StunAddr{host, port, family}` ·
`stun_query`.

### `net/nat.nu` — candidates, NAT-type probe, hole punch

Three things a peer needs before it can reach another:

- **Candidate gathering** — `nat_gather` returns the host candidate (the
  routable local IP, discovered via a throwaway *connected* UDP socket so
  `getsockname` reports it — no `getifaddrs`, fully portable) plus the
  server-reflexive candidate from STUN. IPv4-mapped IPv6 is normalized to
  plain IPv4 so it isn't mistaken for a real v6 path.
- **NAT-type probe** — `nat_probe` queries two STUN servers on the same
  socket. Equal reflexive endpoints ⇒ `nat_type_independent` (cone, punchable);
  differing ⇒ `nat_type_symmetric` (CGNAT — `nat_punchable` is false, so the
  caller skips the punch and goes straight to a relay).
- **UDP hole punch** — `nat_hole_punch` runs a simultaneous-open exchange of
  tokened PING/PONG datagrams (`nat_punch_build` / `nat_punch_parse`; magic
  `"NURP"` + an out-of-band token so the packets are unspoofable and the
  transport can demux them from session data).

### `net/relay.nu` — DERP-style dumb forwarder

When a direct path is impossible, peers reach each other through a relay. The
relay is deliberately **dumb**: Phase 0 already encrypts end-to-end, so the
relay only forwards *opaque* datagrams addressed by destination pubkey — it
never decrypts and never holds session keys. NAT'd peers **dial out** over a
long-lived TCP connection (a peer that can't accept inbound can still hold a
connection open) and register their pubkey.

Frames: `REGISTER` · `FORWARD(dest_pk, payload)` → `DELIVER(src_pk, payload)` ·
`KEEPALIVE`, plus **group multicast** — `GJOIN` / `GLEAVE` / `GSEND`. A `GSEND`
fans one opaque payload out to every other member of a group: **one uplink, N
downlinks**, the bandwidth shape mobile broadcast and group audio need.

Server: `relay_server_start` / `_run` / `_stop` / `_free`. Client: `relay_dial`
· `relay_register` · `relay_send` · `relay_recv` → `?RelayMsg{src, payload}` ·
`relay_group_join` / `relay_broadcast` · `relay_keepalive` · `relay_close`.

---

## Phase 3 — rendezvous (signaling)

`net/rendezvous.nu` is the directory that closes the discovery gap: peers are
addressed by pubkey, but to open a direct path a peer must learn *where another
currently is*. A peer **registers** `pubkey → {candidate endpoints, chosen
relay}`; any peer **looks** another up by pubkey. This is **control plane only**
— the offer/answer of endpoints, never application data or media.

Server: `rz_server_start` / `_run` / `_stop` / `_free`. Client:
`rz_client_connect` · `peer_record_new` / `peer_record_add_endpoint` ·
`rz_register_self` · `rz_lookup_peer` → `*PeerRecord` · `rz_client_close`.

The looked-up endpoints feed `transport_try_direct`; the relay field is the
guaranteed fallback.

---

## Phase 4 — the transport seam

`net/transport.nu` is **the seam**. Everything above it addresses peers by
public key and calls three functions, with no knowledge of NAT, relays,
endpoints, or roaming:

```
transport_send(t, peer_pubkey, payload)        unicast
transport_broadcast(t, group_id, payload)      broadcast to a group
transport_recv(t, max) → ?TransportMsg{src, payload}
```

The payload is arbitrary opaque bytes — a distributed-compute task, a config
delta, an Opus audio frame. Underneath, each peer rides one of two legs:
**direct** (`securedgram`) or **relay** (`relay`).

**Path policy** is a pure state machine: start **relayed** for instant
connectivity, **promote to direct** the moment direct data arrives, **demote**
back to relay after `idle_limit` silent ticks (a mobile direct path went
quiet). The pure functions `transport_note_direct` / `transport_tick` /
`transport_pick` make that policy deterministically testable; the I/O wrappers
dispatch on it. `transport_try_direct(t, pubkey, host, port)` is the hook a
rendezvous candidate drives to begin a direct path.

```
transport_open · transport_add_peer · transport_try_direct
transport_send · transport_broadcast · transport_group_join / _leave
transport_recv · transport_free
```

---

## Phase 5 — membership & failure detection

### `std/lifeguard.nu` — false-positive suppression

The SWIM **Lifeguard** extensions, the part that makes membership survive flaky
mobile links where a slow or roaming node *looks* dead:

- **Local Health Multiplier** — a node measures **its own** health (a probe
  with no ack penalizes it, a success rewards it). Probe intervals *and*
  suspicion timeouts scale by `(1 + LHM)`, so a node on a bad link backs off
  and stops accusing everyone else. `local_health_new` · `lh_award` /
  `lh_penalize` · `lh_scale`.
- **Confirmation-scaled suspicion** — a suspected member gets a long timeout to
  refute; each independent confirmation shortens it toward a floor:
  `timeout(c) = max − (max−min)·log(c+1)/log(k+1)`. Lone suspicions wait
  (a blip); corroborated ones converge fast (a real failure). `suspicion_new` ·
  `suspicion_confirm` · `suspicion_timeout_ns` · `suspicion_expired`.

### `net/membership.nu` — pubkey-keyed SWIM

A SWIM membership table keyed by **public key** (the `std/swim.nu` of §7.2 is
host:port/UDP; this is its overlay sibling), hardened with Lifeguard. The state
machine is pure and **time-injected** — every time-dependent function takes
`now_ns` — so it is fully deterministic and offline-testable.

`PkMember{pubkey, state, incarnation, …}`; `pktable_apply` merges a gossiped
fact with SWIM precedence (higher incarnation wins; at equal incarnation a
worse state wins; dead is sticky; self facts ignored). `pktable_suspect` /
`confirm_suspect` / `sweep` apply the Lifeguard-scaled deadline.
`pktable_pick_probe` / `pktable_pick_relays` / `pktable_gossip` drive the
detector, and `pkmsg_encode` / `pkmsg_decode` carry gossip over the transport.

### `net/failuredetector.nu` — the probe loop

Turns the table into a live detector. A pure, time-injected step machine:
`fd_tick(now)` returns the next action and `fd_on_ack` / `fd_on_gossip` /
`fd_sweep` feed events in.

```
every period          → PING a member (direct)
no ack by direct_to   → escalate to indirect PING-REQ via k relays
no ack by total_to    → suspect (Lifeguard timeout → dead)
a direct ack          → member stays/returns alive (a late ack across a
                        wifi↔cellular roam recovers it instead of declaring
                        it dead)
```

The indirect PING-REQ maps perfectly onto the overlay: if A can't reach B
directly, asking relays C/D to probe B may still reach it via an alternate or
relayed path — so a roaming member stays alive. The transport I/O is a thin
adapter (`examples/membership.nu`); correctness is a deterministic scenario
test, not a live-socket guess.

### Liveness under load — self-refutation + heartbeat

Lifeguard protects the *accuser*; two more mechanisms protect the busy
*accused*, so a node doing real work (or roaming) isn't wrongly evicted.

- **Self-refutation** (`net/membership.nu`) — when a node sees gossip claiming
  *it* is suspect/dead, it bumps its own incarnation past the accuser's
  (`pktable_refute`); the Alive fact its next heartbeat carries then strictly
  outranks the stale Suspect/Dead and reinstates it everywhere. `apply_gossip`
  routes self-facts to refutation rather than dropping them.
- **`dist/heartbeat.nu`** — the *"I am alive"* signal runs on a **dedicated OS
  thread**, not a fiber. NURL fibers are cooperative, so a compute handler in a
  tight loop would starve a fiber-based detector; but the runtime is M:N, so the
  OS preempts threads and the heartbeat fires on its timer **even when every
  worker fiber is pinned at 100% CPU**. It gossips the node's Alive self-fact
  (at its current incarnation, so it also carries any refutation) over its own
  relay connection. `heartbeat_start(table, relay, group, interval, mutex)` /
  `heartbeat_stop`. *(Tested live: a node pinned in a 900M-iteration loop with
  no yield still emits heartbeats — the §7.5 "a 100%-CPU node is not declared
  dead" guarantee, demonstrated.)*

---

## Phase 6 — distributed data

### `dist/ring.nu` — consistent-hash key ownership

Maps keys to the live member that **owns** them, for sharding work and state
across the cluster. Each member sits at `vnodes` points on a 64-bit ring
(virtual nodes → even load and smooth rebalancing); a key is owned by the next
member clockwise, and `ring_owners(key, n)` returns the n distinct members
clockwise (the replica set). Removing a member re-homes **only its keys** — the
consistent-hashing property. FNV-1a/64 hashing, sorted points, binary-search
lookup.

`ring_new` · `ring_add_member` / `ring_remove_member` · `ring_owner` /
`ring_owner_pk` · `ring_owners` · `ring_point_count` · `ring_free`.

### `dist/crdt.nu` — convergent replicated types

State-based CRDTs whose `merge` is commutative, associative, and idempotent, so
replicas converge by exchanging state — no coordination, no consensus.

- **PNCounter** — per-replica inc/dec G-counters; `merge` = element-wise max;
  value = Σinc − Σdec.
- **LwwReg** — last-writer-wins register; higher timestamp wins, ties broken
  deterministically by replica id.
- **OrSet** — observed-remove set; each add carries a unique `(replica, seq)`
  tag, a remove tombstones observed tags, an element is present iff it has a
  non-tombstoned add-tag → **a concurrent add wins over a remove**.

Replicas are small integer ids, supplied by `dist/identity` (below).

### `dist/identity.nu` — stable replica identity

CRDT replica ids must never be **reused** under churn — a new pubkey inheriting
a departed node's PNCounter slot or OR-Set `(replica, seq)` tag space silently
corrupts the value (the merge stays valid, the data is wrong). This registry
maps each peer's static pubkey to a **monotonic, never-reused** replica id:
first sight → the next id; the same pubkey across leave→rejoin → the same id; a
new pubkey never inherits a retired (tombstoned) id. Feed `dist/crdt` /
`dist/replicator` from `identity_of(pubkey)`. `identity_new` / `identity_of` /
`identity_pubkey` / `identity_retire` / `identity_is_live`.

### `dist/replicator.nu` — CRDT gossip wiring, scoped to the ring

Turns a CRDT into something that travels: `*_encode` serializes it to an opaque
byte payload that rides `transport_send` / `transport_broadcast`, and
`*_merge_bytes` decodes a received payload and merges it into the local replica.
Because the op is a CRDT merge, repeated anti-entropy exchanges converge.
`pncounter_encode` / `decode` / `merge_bytes` (and the `lww_*` / `orset_*`
equivalents).

Whole-group broadcast is O(N) per delta and makes the ring decorative, so gossip
is **scoped to the ring**: a key's state lives only on its replica set, and a
delta fans out only to `ring_owners(key, R)` — a non-replica never receives or
stores it. A cheap **digest** (`crdt_digest` / `crdt_in_sync`) drives anti-
entropy: replicas with equal digests skip the transfer; on mismatch the lagging
one pulls. `is_replica` / `replica_fanout` express the routing. This is the same
sharding the compute layer reuses.

---

## The Crown — from distributed state to distributed computation

State convergence is the *setting*; the jewel mounted into it is **verifiable
distributed computation** — work submitted, owned, executed, returned, and
proven correct under churn and load. It adds one invariant to the carried-over
three (pubkey identity; reachability never zero; eventual consistency, no
consensus): **a key is owned by exactly one node per epoch; a task executes
at-least-once; its effect is idempotent or leased.**

### `dist/job.nu` — distributed work dispatch (the keystone)

Submit a task keyed by `k`; `ring_owner(k)` executes it via a registered closure
handler; the result returns to the submitter over the transport and is recorded
by `task_id`, so duplicate delivery is harmless (at-least-once + retry stay
safe). A node that receives a SUBMIT for a key it **no longer owns** (the ring
changed) **forwards** it to the current owner — so killing a worker re-homes its
keys and the job still completes.

`job_node_new` / `job_register(kind, handler)` / `job_submit(key, kind, payload)
→ task_id` / `job_pump` / `job_await(task_id) → ?result`. Handlers are
`( @ ( Vec u ) ( Vec u ) )` closures (opaque bytes → bytes), so a headless
worker cross-compiles to the same RISC-V / wasm targets as everything else — a
Milk-V Duo becomes a real compute node in the ring, not merely a relay.
[`examples/distributed_map.nu`](../examples/distributed_map.nu) shards a
word-count across workers by key and aggregates the result.

### `dist/lease.nu` — fencing for side-effecting tasks

During membership convergence two nodes can briefly both believe they own a
key. CRDT state is safe (merges commute); an external side effect run twice is
not. The standard fencing-token discipline, at the resource: a **monotonic
epoch** per key (bumped on ring change) that a stale owner can't beat
(`lease_admit` refuses a lower epoch), plus an **idempotency key** (the
`task_id`) that dedups a re-delivery. Fence + idempotency = at-most-once across a
split-ownership window *in either ordering*. Pure (no-effect) handlers never call
it and pay zero overhead. `lease_new` / `lease_admit(key, epoch, idem)` /
`lease_token`.

### `dist/sim.nu` — the chaos-simulation harness

How you *really* test all of the above: not flaky multi-process socket runs, but
the **real logic inside a deterministic simulated world** — the approach
FoundationDB / TigerBeetle / `madsim` use, and the reason every layer was built
as a pure, time-injected state machine. A **virtual clock** the harness
advances, an in-process **message bus** carrying the real encoded messages, and
**fault injection applied before the logic sees anything** — seeded per-message
drop, latency + jitter (→ reorder), partition / heal, via an n×n reachability
matrix. A seeded RNG makes every run byte-reproducible; the assertions check
end-state invariants the code can genuinely violate.

`sim_net_new` / `sim_send` / `sim_due` / `sim_partition` / `sim_heal` /
`sim_dropped`. The scenario suite (e.g. `compiler/tests/sim_membership.nu` —
gossip converges under 30% loss + reorder; a partition isolates a fact and a
heal reconverges it) grows toward the headline assertions: cluster stable across
a forced network change; a job completes across a partition + heal; a CPU-pinned
node is not evicted; no double side-effect across split ownership; CRDT
convergence after churn with no slot corruption.

---

## Putting it together

The end-to-end path for "node A updates shared state that node B should see":

```
1.  DISCOVER   A and B register with rendezvous; A looks B up → B's
               candidates + relay.                          (net/rendezvous)
2.  CONNECT    transport_try_direct(B, …): gather candidates, probe NAT type,
               hole-punch, Noise handshake → encrypted direct UDP; if the NAT
               is symmetric, fall back to the relay.    (net/nat, securedgram,
                                                          relay, transport)
3.  MEMBERSHIP both run SWIM over the transport; failure detection with
               Lifeguard keeps the live set accurate across roams.
                                          (net/membership, failuredetector)
4.  OWNERSHIP  the consistent-hash ring (built from the live members) says
               which node owns a key and which are its replicas.   (dist/ring)
5.  STATE      the owner mutates a CRDT and gossips it (encode → broadcast to
               the replica set → merge_bytes on receipt); all replicas
               converge.                          (dist/crdt, dist/replicator)
```

Task semantics are **idempotent + at-least-once**: retries ride the cluster
layer's backoff + circuit-breaker, and CRDT merges make duplicate delivery
harmless.

### A working example

[`examples/replicated_counter.nu`](../examples/replicated_counter.nu) is the
whole top of the stack in ~80 lines: each node increments its own replica slot,
broadcasts its encoded `PNCounter` to the group over the transport, and merges
every counter it receives. Run a relay and several counters with distinct
replica ids and they all converge to the sum of everyone's increments.

```
# terminal 1
./nurl.sh examples/relay.nu 0.0.0.0 47700
# terminals 2..n
./nurl.sh examples/replicated_counter.nu 127.0.0.1 47700 0
./nurl.sh examples/replicated_counter.nu 127.0.0.1 47700 1
```

Other runnable demos: [`stun.nu`](../examples/stun.nu) (public endpoint
discovery), [`nat.nu`](../examples/nat.nu) (candidate gathering + NAT-type
probe), [`relay.nu`](../examples/relay.nu) (a relay daemon),
[`rendezvous.nu`](../examples/rendezvous.nu) (a signaling server),
[`transport.nu`](../examples/transport.nu) (the seam in use),
[`membership.nu`](../examples/membership.nu) (a SWIM node over the overlay).

---

## How it is tested

Two complementary strategies, because the harness intentionally kills loopback
listen sockets (so unit tests can't bind):

- **Deterministic offline tests** cover every pure part — Noise/session
  round-trips, all wire codecs (STUN, relay, rendezvous, gossip, CRDT), the
  NAT-type classifier, the transport path-policy machine, the membership
  state machine, the Lifeguard timeout maths, the consistent-hash properties,
  and the CRDT laws (commutativity, idempotence, convergence, add-wins). These
  are the `*_codec` / `dist_*` / `membership*` / `lifeguard` / `transport_*`
  tests under `compiler/tests/`, each pinned by a golden file and checked
  leak-free under AddressSanitizer.
- **Live verification** runs the socket paths via sandbox-disabled scripts:
  real STUN servers (Google, Cloudflare), loopback relay forwarding + group
  multicast, the transport seam carrying unicast and broadcast, and the
  replicated counter converging across replicas over a relay.
- **Deterministic simulation** (`dist/sim.nu`, the Crown's verification ceiling)
  drives the *real* stdlib logic — the actual membership tables, gossip codec,
  ring, CRDTs, job dispatch, and lease — inside a fully simulated world: a
  virtual clock the harness advances and an in-process message bus it fully
  controls. This is possible only because every layer is a **pure, time-injected
  state machine** (`fd_tick(now)`, `pktable_sweep(now)`, `suspicion_expired`,
  the codecs, the ring, the CRDTs, the lease) — no sockets, no wall-clock, no
  flakiness. Faults (per-message drop, latency + jitter→reorder, partition,
  heal) are injected from a **seeded RNG before the logic sees anything**, so a
  run is byte-reproducible and the headline assertions can genuinely fail. The
  first scenario (`compiler/tests/sim_membership.nu`) asserts that a death fact
  converges to every node *despite 30% packet loss and reorder* (and that
  messages were actually dropped), then that a partition isolates a node from
  the fact and `sim_heal_all` reconverges it. This is the
  FoundationDB/TigerBeetle/madsim approach: catch the rare interleaving in CI,
  deterministically, instead of waiting for it in production.

---

## Status & limitations

The data and control planes are complete and the path
`Phase 0 → 1 → 2 → 4` (a working pubkey overlay with guaranteed reachability)
plus Phases 3, 5, and 6 are in. On top of them the **Crown** compute layer is
landed: stable replica identity (`dist/identity.nu`), self-refutation +
dedicated-OS-thread heartbeat (`dist/heartbeat.nu`), the job-dispatch keystone
(`dist/job.nu`), lease/fencing tokens (`dist/lease.nu`), and the deterministic
chaos-simulation harness (`dist/sim.nu`) with its first converge-under-loss /
partition-heal scenario. The stack is part of NURL's **post-1.0 direction**
(see [`ROADMAP.md`](../ROADMAP.md)); what remains is more simulation coverage,
tuning, and a few tracked deep follow-ups:

- **More chaos scenarios** (Phase 13, ongoing) — beyond converge-under-loss and
  partition-heal: a job completing across a partition + heal, *no double
  side-effect* across split ownership (driving `dist/lease` over the sim bus),
  and a CPU-pinned node that is heartbeating but skipping probes not getting
  evicted.
- **Sim-NAT chaos harness** (Phase 8) — extend the simulator with a NAT model
  (cone vs symmetric, configurable mapping timeout) and a simulated relay, so
  the *transport* layer's network-change behaviour is asserted end-to-end too.
- **Mobile lifecycle tuning** (Phase 7) — adaptive keepalive, network-change
  re-gather, IPv6 happy-eyeballs, battery/radio budget.
- **Ring refinements** — churn hysteresis and weighted virtual nodes.

Known deep follow-ups (no workarounds — these are tracked for a genuine fix):

- **Cross-node replica-id consistency.** `dist/identity.nu` assigns CRDT replica
  ids in local first-seen order, so two nodes can map the same pubkey to
  different slots. Gossiping CRDTs over the sim will expose this; the fix is to
  key CRDTs by pubkey (or derive the id deterministically from the pubkey)
  rather than by local arrival order.
- **Cooperative-scheduler liveness (Tier 2).** The heartbeat runs on a dedicated
  OS thread today (Tier 1), which keeps liveness independent of a long-running
  handler. A fuller fix is compiler-inserted loop back-edge preemption so even a
  tight in-fiber loop yields.
- **Reactor recv-deadline.** A fiber blocked on `tcp_read_chunk` parks on epoll
  without a timer-wheel deadline, so a recv timeout is ignored under the fiber
  reactor; single-process multi-node demos use process-per-node until fiber
  reads are registered on the timer wheel.

The mesh PSK is node-wide today (per-peer PSK is a follow-up).
