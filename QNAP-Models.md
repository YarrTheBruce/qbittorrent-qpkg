# QNAP model → architecture lookup

Which `.qpkg` to install for your NAS, and why. This repo builds one package
per QDK architecture code (see `build.sh`): `x86`, `x86_64`, `arm_64`,
`arm-x19`, `arm-x31`, `arm-x41`. Everything below maps real QNAP model names
to those codes, plus a "not supported" section for models this repo can't
package for at all.

**The reliable way to check** is QTS itself: **Control Panel → System →
System Info → Hardware Information**, or QNAP's own article,
[How do I find out if my NAS uses an ARM or x86 processor](https://www.qnap.com/en/how-to/faq/article/how-do-i-find-out-if-my-nas-uses-an-arm-or-x86-processor).
QNAP has reused similar model numbers (`TS-231` vs `TS-231+` vs `TS-231P`)
across different chips over the years, so name pattern-matching alone isn't
safe — the table below is a starting point, not a substitute for checking
your actual hardware.

One practical shortcut specific to this repo: `arm-x19`, `arm-x31`, and
`arm-x41` all bundle the *identical* `armv7` static `qbittorrent-nox` binary
(see `arch_asset()` in `build.sh`). The three folders only differ in the
platform metadata QTS's installer checks before accepting the package — so
if the "correct" one is rejected, the binary inside another of the three
would have run fine; only try that if you're confident your NAS is genuinely
ARMv7-A class (see the `arm-x19` caveat below before doing that).

## x86_64 — 64-bit Intel/AMD

Most current QNAP NAS from roughly 2016 onward with 64-bit QTS.

| Models | CPU |
|---|---|
| TS-x51A/B/D/E series (later firmware) | Intel Celeron N3xxx–J4xxx generations |
| TS-x53 Pro / A / B / D series | Intel Celeron J1900 → J4125 generations |
| TS-262, TS-264, TS-462, TS-464 | Intel (current small-NAS line) |
| TS-877, TS-877XU(-RP) | AMD Ryzen 5/7 1000-series |
| TS-x73, TS-x73A, TS-x73AU | AMD Ryzen Embedded V1000/V1500B |
| TVS-h1288X, TVS-h1688X | Intel Xeon W-1250 |
| TS-251B and other current TS/TVS Intel/AMD models | various |

## x86 — 32-bit-only Intel/Atom

Older models whose shipped QTS never got a 64-bit build, even where the
underlying CPU is 64-bit-capable.

| Models | CPU |
|---|---|
| TS-239 Pro, TS-239 Pro II(+) | Intel Celeron M |
| TS-259 Pro(+), TS-459 Pro(+/U-RP/U-SP) | Intel Atom D510 |
| TS-439 Pro(+/ II/ II+), SS-439-Pro | Intel Atom |
| TS-559 Pro(+), TS-659 Pro, TS-859 Pro | Intel Atom D510 |
| TS-x51 series (original firmware), TS-269L, TS-469L, TS-651, TS-851 | Intel Celeron/Atom |

## arm_64 — 64-bit ARM (aarch64)

| Models | CPU |
|---|---|
| TS-128A, TS-228A | Realtek RTD1295 (quad-core Cortex-A53) |
| TS-230, TS-328 | Realtek RTD1296 (quad-core Cortex-A53) |
| TS-233, TS-433 | ARM Cortex-A55 quad-core (Realtek RTD1319-family, chip brand not published by QNAP) |
| TS-1635AX | Marvell ARMADA 8040 (quad-core Cortex-A72) |
| TS-435XeU | Marvell OCTEON TX2 CN913x (quad-core Cortex-A72) |

Note: the *original* TS-128/TS-228 (no "A" suffix) use the older Realtek
RTD1195, a 32-bit Cortex-A7 chip — those are **not** `arm_64`; see `arm-x41`
below.

## arm-x31 — Mindspeed/Freescale Comcerto (ARMv7, Cortex-A9 dual-core 1.2GHz)

| Models | CPU |
|---|---|
| TS-131, TS-231, TS-431 (original, no suffix) | Comcerto C2000 / "Freescale ARM Cortex-A9" per QNAP's own spec pages |

## arm-x41 — Annapurna Labs Alpine (ARMv7, Cortex-A15-class)

| Models | CPU |
|---|---|
| TS-231+, TS-431+ | Alpine AL-212 dual-core 1.4GHz |
| TS-131P, TS-231P, TS-431P | Alpine AL-212 dual-core 1.7GHz |
| TS-231P2, TS-431P2, TS-531X | Alpine AL-314 quad-core 1.7GHz |
| TS-131K, TS-231K, TS-431K | Alpine AL-214 quad-core 1.7GHz |
| TS-128, TS-228 (original, no "A" suffix) | Realtek RTD1195 (32-bit Cortex-A7) |

Community-maintained compatibility notes (e.g. other QPKG projects' READMEs)
disagree with QNAP's own product announcements on whether the `+`/`P`
variants belong under `arm-x31` or `arm-x41`. This table follows QNAP's own
press releases confirming the actual chip (Alpine vs. Comcerto), which is
the more direct source — but if a package built from this repo's `arm-x41`
folder is rejected by QTS on one of these models, try `arm-x31` (or vice
versa); as noted above, the binary inside is identical either way.

## arm-x19 — unresolved, treat with caution

This repo's `build.sh` currently assumes `arm-x19` corresponds to
ARMv7-A hardware (paired with the same `armv7` static binary as `arm-x31`
and `arm-x41`). Independent research for this table did not confirm that.
The most concrete evidence found (a real-world QPKG compatibility list from
another QNAP package project, cross-checked against confirmed CPU specs for
individual models) instead points to `arm-x19` corresponding to QNAP's
**Marvell Kirkwood** line — genuinely **ARMv5TE**, not ARMv7:

| Models | CPU |
|---|---|
| TS-119, TS-219, TS-419 (and P/P+/P II/U/U+/U II variants) | Marvell 88F6281 (Kirkwood), ARMv5TE |
| TS-221, TS-421(U) | Marvell 88F6282 (Kirkwood), ARMv5TE |

ARMv5TE is *below* the ARMv6 hard-float baseline that the upstream
`qbittorrent-nox-static` project requires (the same reason `arm-x09` is
excluded from this repo entirely — see below). If this mapping is correct,
the `armv7` binary this repo currently packages as `arm-x19` would not
actually run on the real hardware QTS identifies as `arm-x19` — i.e. this
architecture may not have any real device it works on. This hasn't been
verified on real hardware either way, and no change has been made to
`build.sh` to remove it pending confirmation. If you own one of the models
above, testing it (and reporting back) would help resolve this.

## Not supported by this repo

No matching static `qbittorrent-nox` build exists for these — the QPKG
can't be produced at all, regardless of the model.

| QDK arch | Why | Example / affected models |
|---|---|---|
| `arm-x09` | ARMv5TE, below the ARMv6 hard-float baseline | No specific QNAP retail model could be confirmed for this code during research — possibly unused/reserved, or extremely old/rare hardware. If `arm-x19` above does turn out to mean Kirkwood (see caveat), then all Kirkwood-family models (TS-1xx/2xx/4xx-series listed under `arm-x19` above, plus similar-era TS-109/TS-209/TS-112/TS-212/TS-412) should be treated as unsupported regardless of which QDK code QTS actually uses for them. |
| `x86_ce53xx` | Narrow legacy QNAP variant | Model unconfirmed; no sensible 1:1 match to an upstream static build exists |
| `riscv64` | No QNAP hardware uses this ISA | — |

If you test any model above (in the caveated `arm-x19` row or the
unsupported table) and it works, or definitively doesn't, that's worth
reporting back — see the main [README](README.md#architecture-support).
