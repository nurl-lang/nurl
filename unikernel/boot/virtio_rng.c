/*
 * NURL unikernel — unikernel/boot/virtio_rng.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Entropy from a virtio-rng device, for a machine whose instruction
 * set does not have any.
 *
 * WHY THIS IS C, AND IN THE BOOT LAYER
 *
 * `getrandom` is a libc-level call: NURL asks the runtime, the runtime
 * asks the platform, and the platform answers from the machine. On
 * x86 that answer is RDRAND and on AArch64 it is RNDR — two
 * instructions, both in platform_<arch>.c. RISC-V has neither (the
 * `seed` CSR is the optional Zkr extension and QEMU's rv64 CPU does
 * not implement it), so on that machine the answer has to come from a
 * DEVICE, and it has to be available at exactly the same layer the
 * other two answers are: below the runtime, with no NURL module
 * linked, before anything above has been arranged.
 *
 * That is why this does not use `stdlib/hal/virtq.nu`, which is the
 * project's real virtqueue implementation and the one the network
 * driver uses. This is one queue, one buffer, no negotiation beyond
 * the version bit, and it must work for a program that never links
 * the socket layer. The two are the same protocol at different
 * layers, not two implementations of one thing — and the modern MMIO
 * register offsets below are the same numbers `hal/virtio.nu` names,
 * kept in the same order so the two can be read side by side.
 *
 * The device is trusted for BYTES, not for the count: it is asked for
 * n bytes and told how many it wrote, and a device claiming to have
 * written more than the buffer holds is refused rather than believed.
 */

typedef unsigned long long u64;
typedef unsigned int       u32;
typedef unsigned short     u16;
typedef unsigned char      u8;

/* ── the modern virtio-mmio register file ───────────────────────── */
#define R_MAGIC          0x000
#define R_VERSION        0x004
#define R_DEVICE_ID      0x008
#define R_DEV_FEATURES   0x010
#define R_DEV_FEAT_SEL   0x014
#define R_DRV_FEATURES   0x020
#define R_DRV_FEAT_SEL   0x024
#define R_QUEUE_SEL      0x030
#define R_QUEUE_NUM_MAX  0x034
#define R_QUEUE_NUM      0x038
#define R_QUEUE_READY    0x044
#define R_QUEUE_NOTIFY   0x050
#define R_INT_STATUS     0x060
#define R_INT_ACK        0x064
#define R_STATUS         0x070
#define R_Q_DESC_LO      0x080
#define R_Q_DESC_HI      0x084
#define R_Q_DRIVER_LO    0x090
#define R_Q_DRIVER_HI    0x094
#define R_Q_DEVICE_LO    0x0a0
#define R_Q_DEVICE_HI    0x0a4

#define VIRTIO_MAGIC     0x74726976   /* "virt" */
#define DEV_ID_ENTROPY   4

#define S_ACKNOWLEDGE    1
#define S_DRIVER         2
#define S_DRIVER_OK      4
#define S_FEATURES_OK    8
#define S_FAILED         128

#define F_VERSION_1_BIT  32           /* in the high feature word     */

#define VRING_DESC_F_WRITE 2

#define QSIZE 8                        /* one request at a time; the
                                        * queue exists because the
                                        * protocol has one, not because
                                        * this driver pipelines */

struct vring_desc {
    u64 addr;
    u32 len;
    u16 flags;
    u16 next;
};
struct vring_avail {
    u16 flags;
    u16 idx;
    u16 ring[QSIZE];
    u16 used_event;
};
struct vring_used_elem {
    u32 id;
    u32 len;
};
struct vring_used {
    u16 flags;
    u16 idx;
    struct vring_used_elem ring[QSIZE];
    u16 avail_event;
};

/* The rings live in .bss, which is identity-mapped RAM on every board
 * this runs on — the device is handed physical addresses and there is
 * no IOMMU in the picture. Alignment is the spec's: 16 for the
 * descriptor table, 2 for the available ring, 4 for the used ring;
 * page alignment costs nothing here and satisfies all three. */
static struct vring_desc  rng_desc[QSIZE]  __attribute__((aligned(4096)));
static struct vring_avail rng_avail        __attribute__((aligned(4096)));
static struct vring_used  rng_used         __attribute__((aligned(4096)));
static u8                 rng_buf[256]     __attribute__((aligned(64)));

static u64 rng_base;            /* 0 = no device found (or not looked) */
static int rng_ready;
static u16 rng_last_used;

static inline u32 mmio_r32(u64 base, u32 off) {
    return *(volatile u32 *)(unsigned long)(base + off);
}
static inline void mmio_w32(u64 base, u32 off, u32 v) {
    *(volatile u32 *)(unsigned long)(base + off) = v;
}

/* Bring one device up. 1 on success. Every failure leaves FAILED in
 * the status register, which is what the spec asks a driver to do and
 * what makes a half-initialised device visible to anyone looking. */
static int rng_init_at(u64 base) {
    if (mmio_r32(base, R_MAGIC) != VIRTIO_MAGIC) return 0;
    if (mmio_r32(base, R_VERSION) != 2) return 0;      /* legacy: refuse */
    if (mmio_r32(base, R_DEVICE_ID) != DEV_ID_ENTROPY) return 0;

    mmio_w32(base, R_STATUS, 0);                        /* reset        */
    while (mmio_r32(base, R_STATUS) != 0) { }
    mmio_w32(base, R_STATUS, S_ACKNOWLEDGE);
    mmio_w32(base, R_STATUS, S_ACKNOWLEDGE | S_DRIVER);

    /* Features: the entropy device offers nothing this driver wants,
     * but VIRTIO_F_VERSION_1 must be accepted or a modern device
     * refuses FEATURES_OK — which is the whole difference between the
     * modern and legacy protocols. */
    mmio_w32(base, R_DEV_FEAT_SEL, 1);
    u32 hi = mmio_r32(base, R_DEV_FEATURES);
    mmio_w32(base, R_DRV_FEAT_SEL, 1);
    mmio_w32(base, R_DRV_FEATURES, hi & (1u << (F_VERSION_1_BIT - 32)));
    mmio_w32(base, R_DRV_FEAT_SEL, 0);
    mmio_w32(base, R_DRV_FEATURES, 0);

    mmio_w32(base, R_STATUS, S_ACKNOWLEDGE | S_DRIVER | S_FEATURES_OK);
    if (!(mmio_r32(base, R_STATUS) & S_FEATURES_OK)) {
        mmio_w32(base, R_STATUS, S_FAILED);
        return 0;
    }

    mmio_w32(base, R_QUEUE_SEL, 0);
    if (mmio_r32(base, R_QUEUE_READY) != 0) {           /* already up?  */
        mmio_w32(base, R_STATUS, S_FAILED);
        return 0;
    }
    u32 max = mmio_r32(base, R_QUEUE_NUM_MAX);
    if (max == 0) { mmio_w32(base, R_STATUS, S_FAILED); return 0; }
    u32 n = max < QSIZE ? max : QSIZE;
    mmio_w32(base, R_QUEUE_NUM, n);

    for (int i = 0; i < QSIZE; i++) {
        rng_desc[i].addr = 0; rng_desc[i].len = 0;
        rng_desc[i].flags = 0; rng_desc[i].next = 0;
    }
    rng_avail.flags = 0; rng_avail.idx = 0;
    rng_used.flags = 0;  rng_used.idx = 0;
    rng_last_used = 0;

    u64 d = (u64)(unsigned long)&rng_desc[0];
    u64 a = (u64)(unsigned long)&rng_avail;
    u64 u = (u64)(unsigned long)&rng_used;
    mmio_w32(base, R_Q_DESC_LO,   (u32)d);
    mmio_w32(base, R_Q_DESC_HI,   (u32)(d >> 32));
    mmio_w32(base, R_Q_DRIVER_LO, (u32)a);
    mmio_w32(base, R_Q_DRIVER_HI, (u32)(a >> 32));
    mmio_w32(base, R_Q_DEVICE_LO, (u32)u);
    mmio_w32(base, R_Q_DEVICE_HI, (u32)(u >> 32));
    mmio_w32(base, R_QUEUE_READY, 1);

    mmio_w32(base, R_STATUS, S_ACKNOWLEDGE | S_DRIVER | S_FEATURES_OK | S_DRIVER_OK);
    return 1;
}

/* Find and initialise the first virtio-rng device among the bases the
 * device tree reported. Returns 1 when one is ready. Called lazily, on
 * the first request: a program that never asks for entropy pays
 * nothing, and one that asks on a machine without a device gets an
 * answer rather than a boot-time panic it did not cause. */
int virtio_rng_start(const u64 *bases, int n) {
    if (rng_ready) return 1;
    for (int i = 0; i < n; i++) {
        if (!bases[i]) continue;
        if (rng_init_at(bases[i])) {
            rng_base = bases[i];
            rng_ready = 1;
            return 1;
        }
    }
    return 0;
}

/* Ask the device for up to `len` bytes; returns how many it wrote, or
 * -1 if there is no device. Polls the used ring — this runtime takes
 * no interrupts, and an entropy read happens a handful of times in a
 * program's life. */
long long virtio_rng_read(void *dst, unsigned long len) {
    if (!rng_ready) return -1;
    if (len == 0) return 0;
    if (len > sizeof rng_buf) len = sizeof rng_buf;

    rng_desc[0].addr  = (u64)(unsigned long)rng_buf;
    rng_desc[0].len   = (u32)len;
    rng_desc[0].flags = VRING_DESC_F_WRITE;   /* the DEVICE writes it */
    rng_desc[0].next  = 0;

    /* Publish, then tell the device. The barrier is not decoration:
     * the device may read the ring the instant the index moves, and
     * the descriptor has to be visible first. */
    rng_avail.ring[rng_avail.idx % QSIZE] = 0;
    __asm__ __volatile__("" ::: "memory");
    rng_avail.idx++;
    __asm__ __volatile__("" ::: "memory");
    mmio_w32(rng_base, R_QUEUE_NOTIFY, 0);

    /* Bounded wait. A device that never answers is a broken device,
     * and spinning forever inside a key generation is the worst place
     * to hang; the caller's panic path is a better answer. */
    unsigned long spins = 0;
    while (rng_used.idx == rng_last_used) {
        if (++spins > 100000000UL) return -1;
        __asm__ __volatile__("" ::: "memory");
    }
    u32 got = rng_used.ring[rng_last_used % QSIZE].len;
    rng_last_used++;
    mmio_w32(rng_base, R_INT_ACK, mmio_r32(rng_base, R_INT_STATUS));

    /* The device says how much it wrote. Believe the bytes, not the
     * count: a device claiming more than the buffer holds is refused
     * rather than allowed to describe a copy past the end of it. */
    if (got > len) return -1;
    u8 *d = (u8 *)dst;
    for (u32 i = 0; i < got; i++) d[i] = rng_buf[i];
    return (long long)got;
}
