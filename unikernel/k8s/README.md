# A NURL server, with and without a machine under it

`server.nu` is an HTTP server. It builds two ways, and not one line of
it changes between them:

* **As a machine.** `build_unikernel.sh` turns it into a 616 KB
  bootable PVH kernel, and `Dockerfile` puts that kernel next to a
  hypervisor. Under the program there is no operating system: the
  router, the HTTP parser, the TCP stack, the ARP cache, the DHCP
  client, the scheduler and the allocator are all NURL from this
  repository, and the bottom edge is a virtio-net device and a CPU.
* **As a process.** `build_static_image.sh` links it into a 1.5 MB
  static Linux binary in a `FROM scratch` container, where the node's
  kernel answers the socket calls instead.

Both run as ordinary, unprivileged Kubernetes workloads.
[Measured numbers](#measured) and [what the exercise
found](#two-things-this-exercise-found) are below; the fastest way to
believe any of it is to run it.

## Run it, in order of how much you have to install

You need `clang`, `qemu-system-x86_64`, and `./build.sh` run once (for
`build/nurlc`). Docker and a cluster are optional and come later.

### 1. No container, no Kubernetes

```sh
unikernel/build_unikernel.sh unikernel/k8s/server.nu -o build/unikernel/k8sd.elf
unikernel/k8s/smoke.sh
```

`smoke.sh` boots the image, waits for the guest to say it is
listening, asks it all four routes, and asserts two things a working
server has to do and a broken one still looks fine without: answer
inside a cold-start budget, and answer a second client while a first
holds a connection open. Expect seven `PASS` lines.

To poke at it by hand instead, this is the whole invocation — no
initrd, no bootloader, no disk, and `-netdev user` so it needs no
privileges:

```sh
qemu-system-x86_64 -M microvm,acpi=off,rtc=off \
    -accel kvm -cpu max -m 256 \
    -nodefaults -no-reboot -no-user-config \
    -global virtio-mmio.force-legacy=false \
    -kernel build/unikernel/k8sd.elf \
    -append "tsc_khz=3500000 wallclock=$(date +%s) pod=laptop port=8080 platform=unikernel" \
    -device virtio-net-device,netdev=n0 \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:8080-:8080 \
    -serial stdio -display none
# then, in another terminal:
curl localhost:8080/ ; curl localhost:8080/info
```

`-accel kvm` needs `/dev/kvm`; drop to `-accel tcg` without it and set
`tsc_khz` to your host's nominal TSC frequency — see [the
clock](#the-clock-which-the-guest-refuses-to-invent), which is the one
thing about this target that will surprise you.

### 2. As a container

```sh
unikernel/k8s/build_image.sh                      # 86 MB: alpine + qemu + the guest
docker run --rm -p 8080:8080 -e POD_NAME=laptop nurl-unikernel-httpd:0.1.0
curl localhost:8080/

unikernel/k8s/build_static_image.sh               # 1.56 MB: the binary, and nothing
docker run --rm -p 8081:8080 -e pod=laptop -e platform=linux nurl-static-httpd:0.1.0
curl localhost:8081/
```

### 3. On Kubernetes

The manifests reference bare local tags, so a local cluster needs the
image loaded rather than pulled:

```sh
kind create cluster                               # or: minikube start
kind load docker-image nurl-unikernel-httpd:0.1.0 # or: minikube image load ...
kubectl apply -f unikernel/k8s/deploy.yaml
kubectl -n nurl-unikernel port-forward svc/nurl-unikernel 8080:80
curl localhost:8080/info
```

`deploy-static.yaml` is the same for the other build, in the
`nurl-static` namespace. `ingress.yaml` is an example, and says which
two lines you have to change.

For a real cluster: retag to your registry (`build_image.sh -t
registry.example.com/you/nurl-unikernel-httpd:0.1.0 --push`), put that
reference in the manifest's `image:`, and add an `imagePullSecrets:`
entry if the registry needs one. Nothing else in the manifests is
site-specific.

Routes: `/` (text), `/healthz` (probes), `/info` (JSON), `/metrics`
(Prometheus).

## What the pod is allowed to do: nothing in particular

QEMU's user-mode network stack is ordinary userspace code, so the
forwarded port needs no tap device, no `CAP_NET_ADMIN` and no
`NET_RAW`. The pod therefore runs `runAsNonRoot`,
`readOnlyRootFilesystem`, all capabilities dropped, `RuntimeDefault`
seccomp, no privileged flag, no `/dev/kvm`, no `runtimeClass`. It is as
unprivileged as a static file server, and what it serves is a machine.

`/dev/kvm` is used *if the node hands it over* — `entrypoint.sh` checks
and falls back to TCG — but `deploy.yaml` does not ask for it, because
asking means either a privileged container or a device plugin. The
measurements below are the ones without it;
[**giving the guest KVM**](#optional-giving-the-guest-kvm) is a section
of its own, with the numbers it buys and the two things that bite.

The one hard constraint is `nodeSelector: kubernetes.io/arch: amd64`.
PVH is an x86 boot protocol; on AArch64 the same build emits a flat
`Image` instead (see `unikernel/README.md`), which is a different
container-image build, not a different manifest.

## Measured

On a 6-core x86_64 desktop (nominal TSC 3.5 GHz), 2026-08-27. The
cluster row is a two-node amd64 k3s, with `kubectl top` after the
traffic stopped — the kubelet's own probes are in that figure.

| | unikernel + QEMU | static binary |
|---|---|---|
| artifact | 616 KB bootable ELF | 1.5 MB static binary, stripped |
| container image | 86 MB (alpine + `qemu-system-x86_64`) | **1.56 MB** (`FROM scratch`) |
| start → listening | 38 ms (KVM), 63 ms (TCG) | — |
| start → first request answered | 66 ms (KVM), 90 ms (TCG) | **11 ms** |
| container start → probe-Ready | 1–2 s, and that is the probe's period | 1–2 s, likewise |
| idle in the cluster | 22–40 millicores, 15–17 MiB | **1 millicore, under 1 MiB** |
| memory handed to it | 256 MB; it touches ~16 MB | 64 MB limit; it touches ~1 MB |
| pod privileges | none | none |
| what is under it | a virtio-net device and a CPU | the node's Linux kernel |

The unikernel's idle figure is what makes it a resident rather than a
demo: the guest halts on `hlt` between poller ticks (tickless idle off
the LAPIC timer), so an idle machine is not a spinning host core.

## Three things this exercise found

None of them was visible to a test that asked "does it answer". Two
cost every boot a fixed, clock-scaled delay; the third cost the pod its
life.

**The first DHCPREQUEST waited a full retransmit backoff.**
`dhcp_handle` moved SELECTING → REQUESTING on an OFFER and set
`next_send_ms = now + dhcp_retry_base_ms`, so the REQUEST — the answer
to an offer already in hand — went out four seconds later. Sixty-eight
state-machine assertions passed the whole time: the client bound, with
the right address, the right lease and the right timers. Nothing
asserted *when*. `compiler/tests/net_dhcp.nu` now does, and the
assertion fails against the old code.

**The first frame to an unresolved next hop is never the frame.**
`stack_tx_ip4` owns no queues by design: on an ARP miss it sends the
request and returns `tx_arp_pending`, leaving the retry to the caller —
"which for TCP is free, because a segment that did not go out is
exactly what its retransmit timer is already for". It is free only when
someone is already waiting. For a server the first such segment is the
SYN-ACK of the first connection it ever accepts, and the retransmit
timer is one second: a machine that had been listening for 40 ms
answered its first client 1000 ms later. `stack_arp_prime` resolves a
hop with nothing pending, and the guest primes its gateway at the end
of DHCP — every client arriving through a hypervisor's user-mode
network is off-subnet and routes via that gateway.

Together: 5.1 s to a first answer became 66 ms.

**One connection at a time is one connection too few.** `server_run`
accepts, serves keep-alive until the peer leaves or the 30 s idle
timeout fires, and only then accepts again. A pod has two clients
before it has any users — the readiness probe and the liveness probe —
and one `curl` left open is enough to make the kubelet's probes time
out and the pod get replaced. It happened here, in the cluster, and the
event log is how it was found rather than any test. Both builds now
call `server_run_async`, which gives each connection a fiber: on the
guest those fibers are the whole concurrency story anyway (one vCPU,
cooperative, the device poller is already one of them); hosted, the M:N
scheduler spreads them over worker threads.

That change needed one thing the freestanding runtime did not have:
`nurl_fiber_spawn_owned`, the spawn that frees the closure environment
its fiber captured. `runtime_bare.c` has it now — without it the guest
could not link the async server at all, which is a fair description of
how much the async path had been exercised there.

`smoke.sh` asserts both the cold-start budget and the held-open
connection rather than printing them, because all three bugs passed
every does-it-answer test in the repository.

## The clock, which the guest refuses to invent

Under KVM the guest reads the TSC frequency from CPUID leaf
0x40000010. Under TCG there is no such leaf, and QEMU's `rdtsc` is the
*host's* `rdtsc` — so the honest `tsc_khz=` is the host's nominal TSC
frequency, not QEMU's documented 1 GHz. `entrypoint.sh` derives it
(the kernel's own figure, else Intel's nominal frequency out of
`/proc/cpuinfo`'s model name, else the current core frequency) and the
guest's clock then tracks the host's to within 0.2 %.

Passing 1000000 on a 3.5 GHz host made every guest timer — including
DHCP's — run 3.5× fast, which is the kind of error that makes a timing
bug look like a working system.

## Configuration

Everything the launcher says reaches the guest as a kernel command line
key, which `boot/cmdenv.c` presents as an environment variable. The
static build reads the same keys straight from the environment.

| key | set by | meaning |
|---|---|---|
| `pod` | `POD_NAME` (downward API) | printed by `/` and `/info` |
| `port` | `GUEST_PORT` | the port the server binds |
| `platform` | the launcher | `unikernel`, `linux`, or `unknown` |
| `tsc_khz` | derived by `entrypoint.sh` | TSC frequency (guest only) |
| `wallclock` | `date +%s` | boot epoch — without it the guest thinks it is 1980 |

`platform` is something the launcher states rather than something the
program asserts. A program cannot find out what is beneath it, and a
binary that says "no operating system" while running as a Linux process
is a claim its reader cannot check — so the launcher says
(`platform=unikernel` on the kernel command line, `platform: linux` in
the static manifest) and the program repeats it.

## Before the static build stops being a proof of concept

* **Static glibc and NSS.** The link warns about `getaddrinfo`,
  `getpwuid` and `getgrgid`: they resolve through `dlopen`'d NSS
  modules that a static binary has no loader for. This server calls
  none of them, so the warning is accurate and harmless *here* — a
  program that resolves a name would fail at runtime, not at link time.
  Building against musl (`zig cc -target x86_64-linux-musl`) removes
  the trap instead of dodging it.
* **The link bypasses `nurl.sh`.** There is no hook for link flags, so
  `build_static_image.sh` spells the link out itself and thereby skips
  nurl.sh's ThinLTO configuration and feature-library probing. A
  `NURL_LDFLAGS` hook would be the smaller, more honest fix.
* **What the static build gives up** is the machine — the TCP stack,
  ARP, DHCP, the scheduler and the allocator become the node's, and the
  pure-NURL network stack, the thing that surfaced both bugs above, no
  longer runs in production — and the isolation boundary, which is the
  only reason left to pay for a hypervisor once a workload is
  stateless.

## Optional: giving the guest KVM

`kvm-device-plugin.yaml` runs a device plugin on the nodes that have
`/dev/kvm`, after which a workload asks for `devic.es/kvm: 1` and stays
exactly as unprivileged as it was — no privileged flag, no hostPath, no
capability added. The scheduler, rather than a hand-maintained
nodeSelector, knows where the device is.

```sh
kubectl apply -f unikernel/k8s/kvm-device-plugin.yaml
kubectl label node <node> devic.es/kvm=true
kubectl -n nurl-unikernel patch deploy nurl-unikernel --type strategic -p '
  {"spec":{"template":{"spec":{
     "securityContext":{"supplementalGroups":[993]},
     "containers":[{"name":"qemu","resources":{"limits":{"devic.es/kvm":"1"}}}]}}}}'
```

`993` is the gid of the `kvm` group **on that node** (`getent group
kvm`), not a constant. The device arrives in the container with the
host's ownership — `root:kvm 0660` — and a container running as a
non-root user is not in that group. What makes this worth spelling out
is the failure mode: QEMU's answer to `EACCES` on `/dev/kvm` is to
emulate instead, so the pod comes up, passes its probes, serves correct
answers, and is simply slower. `entrypoint.sh` logs `accel=kvm` or
`accel=tcg` on its first line; that line is the check.

### What it buys, measured

Same image, same node, same pod spec, one with the device and one
without. Latency and CPU are 2000 sequential keep-alive requests to
`/healthz`; the CPU figure is the container's own cgroup accounting
(`cpu.stat usage_usec`), not a sampled estimate. Idle is 30 s with only
the kubelet's probes.

| | KVM | TCG |
|---|---|---|
| boot: `entrypoint` → listening | 35–45 ms | 53–97 ms |
| wall time per request | 1.15–1.17 ms | 1.48–1.82 ms |
| **container CPU per request** | **276–306 µs** | **940–991 µs** |
| idle | 5 millicores | 22 millicores |

The wall-clock difference is the least interesting number here — it is
mostly client and network path. The CPU is the one that decides whether
this is a resident or a demo: **~3.3× less CPU per request and ~4× less
at idle**, on a workload whose guest is halting between poller ticks
either way.

### The trade nobody announces

Requesting the resource collapses the deployment onto the nodes that
have it. On a cluster where one node has `vmx` and the others do not,
adding one line to a manifest converts a two-node deployment into a
single-node one — availability traded for speed, silently, unless
somebody says so. This section is that somebody.
