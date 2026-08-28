# qbittorrent-qpkg

A QNAP QPKG that packages [qBittorrent](https://www.qbittorrent.org/) (headless
`qbittorrent-nox` + WebUI) for QNAP NAS. Builds for x86, x86_64, arm_64, and
three ARMv7 variants — see [Architecture support](#architecture-support) for
which of those are actually verified working vs. packaged-but-untested.

The package name (`QPKG_NAME`) is `YTBqbittorrent`, not plain `qbittorrent` —
deliberately prefixed so installing this doesn't collide with or overwrite
any existing/official `qbittorrent` QPKG already on the NAS (QTS treats
matching `QPKG_NAME` as the same app for upgrade/replace purposes).

The package doesn't compile qBittorrent from source. It downloads the latest
static `qbittorrent-nox` build from
[userdocs/qbittorrent-nox-static](https://github.com/userdocs/qbittorrent-nox-static)
(a widely used, actively maintained source of static qBittorrent + libtorrent
builds) and wraps it with a QDK-style install/init script.

## Layout

```
package_routines   # install/remove hooks, run by QNAP's generic installer
qpkg.cfg           # package metadata (name, version, ports, ...)
shared/            # architecture-independent files -> installed as-is
  qbittorrent.sh   # start/stop init script (App Center "Start/Stop" button)
x86/, x86_64/, arm_64/, arm-x19/, arm-x31/, arm-x41/
                   # one qbittorrent-nox binary per architecture,
                   # fetched by build.sh, not committed
icons/             # optional App Center icons (YTBqbittorrent[.gif|_80.gif|_gray.gif])
build.sh           # fetches the QDK toolkit + binary and builds the .qpkg
```

## Building

```
./build.sh
```

This will:
1. Fetch QNAP's official [QDK](https://github.com/qnap-dev/QDK) build tool
   into `.qdk-toolkit/` (git-ignored — it's a build dependency, not part of
   the package) and compile its `qpkg_encrypt` helper.
2. Download the latest static `qbittorrent-nox` binary for each supported
   architecture (see below).
3. Run `qbuild` to produce one `build/YTBqbittorrent_<version>_<arch>.qpkg`
   per architecture.

Requires `git`, `curl`, and a C compiler (`cc`/`gcc`) on the build machine.
Nothing QNAP-specific is required to build — `qbuild` is a portable shell
script.

### Automated releases

[`.github/workflows/release.yml`](.github/workflows/release.yml) checks
daily (and can be run manually from the Actions tab) whether
`qbittorrent-nox-static` has published a newer qBittorrent version than
this repo's latest [GitHub Release](../../releases). If so, it runs
`build.sh` and publishes all six `.qpkg` files as a new release, so you
don't need to build locally at all unless you specifically want to.

## Installing

Grab a `.qpkg` for your architecture from either `build/` (if you built
locally) or the [Releases page](../../releases) (published automatically —
see above). Then in QTS: **App Center → (⚙️ gear icon, top right) → Install
Manually**, then browse to that file.

You'll likely hit a **"Digital Signature Warning: This application does not
have a valid digital signature..."** dialog — this is expected and safe to
click through. It's QTS checking the package against QNAP's own proprietary
code-signing PKI (`codesigning.qnap.com.tw`), which is only issued to
approved QNAP developers/publishers, not available for community packages.
Essentially every homebrew QPKG not distributed through QNAP's official App
Center listing triggers this same warning.

## Usage notes

- **WebUI**: `http://<nas-ip>:6262/` by default (8080 is QNAP's own admin
  WebUI port, so qBittorrent uses 6262 instead). The port is read from the
  QPKG's `Web_Port` field in `/etc/config/qpkg.conf` (editable via App
  Center → qBittorrent → settings icon).
- **First login**: qBittorrent 5.x generates a random temporary admin
  password on first start instead of a fixed default. The init script
  copies it to QTS's **Control Panel → System Logs → System Event Logs**
  (as an Error-level entry — the only severity QNAP's own QDK material
  actually documents a working example for; arguably fitting anyway, since
  it demands action) on that first start, so you don't need SSH
  access to find it. It's also written to the package's own log:
  `/share/<volume>/.qpkg/YTBqbittorrent/data/qbittorrent-nox.log` (look for a
  line starting "The WebUI administrator password was not set..."). Change
  it immediately under WebUI → Options → Web UI — note the password is
  visible in plaintext to anyone who can read the System Event Log (i.e.
  any NAS admin), same as it already was in the log file.
- **Data location**: qBittorrent's profile (settings, resume data, and its
  *default* download save path) lives under
  `<install path>/YTBqbittorrent/data/`. **Uninstalling the package deletes
  this directory**, including any torrents saved to the default path. Set
  a save path on one of your data volumes (e.g. `/share/Download`) under
  WebUI → Options → Downloads before adding torrents, if you want it to
  survive an uninstall/reinstall.

## Architecture support

| QNAP arch  | Example models                          | Static build used | Status |
|------------|------------------------------------------|--------------------|--------|
| `x86_64`   | TS-251B and most modern Intel/AMD models | `x86_64`           | **Verified** — this is the only arch actually run and tested (see commits/PRs) |
| `x86`      | Older 32-bit Intel/Atom models            | `x86`              | Untested |
| `arm_64`   | 64-bit ARM models (e.g. Realtek RTD1296)  | `aarch64`          | Untested |
| `arm-x19`  | Marvell Armada XP models (e.g. TS-x21)    | `armv7`            | Untested |
| `arm-x31`  | Annapurna Alpine models (e.g. TS-x31)     | `armv7`            | Untested |
| `arm-x41`  | Annapurna Alpine models (e.g. TS-x31+)    | `armv7`            | Untested |

"Untested" means: `build.sh` successfully packages a `.qpkg` with the
correct binary for that architecture (confirmed by extracting each build
and checking the embedded ELF header matches — e.g. `arm-x31` really does
contain an ARM EABI5 binary, `arm_64` an aarch64 one, etc.), but nothing
has actually *run* it — this dev environment is x86_64 and can't execute
the other architectures' binaries. Packaging correctness isn't the same
as runtime correctness (wrong ABI/kernel-version assumptions wouldn't
show up until you try to start it on real hardware). Treat non-x86_64
builds as a starting point, not a guarantee.

Not supported at all: `arm-x09` (ARMv5 Kirkwood, e.g. old TS-119/TS-219/
TS-419 models) has no matching upstream static build — the static builds'
minimum ARM baseline is ARMv6 hard-float — and those models are old/
resource-constrained enough that qBittorrent probably wouldn't run well
regardless. `x86_ce53xx` (a narrow legacy QNAP variant) and `riscv64` (no
QNAP hardware uses it) are skipped for the same reason: no sensible 1:1
match to an upstream build exists.

If you test one of the untested architectures and it works (or doesn't),
that's worth reporting back so this table can be corrected.

## Versioning

`QPKG_VER` is `<qbt_version>-<QPKG_REVISION>`, e.g. `5.2.3-1.0` — the
qBittorrent version and this package's own revision are tracked
independently. Bump `QPKG_REVISION` (near the top of `build.sh`, or
override with `QPKG_REVISION=1.1 ./build.sh`) when shipping a
packaging-only change — an init script fix, a new configurable option,
etc. — without waiting on a new upstream qBittorrent release. Reset it to
`1.0` whenever `qbt_version` moves to a new upstream release.

Note: how QTS compares two `QPKG_VER` strings at upgrade time (e.g.
whether it correctly treats `5.2.3-1.1` as newer than `5.2.3-1.0`) hasn't
been verified against real hardware, same caveat as the
[architecture support](#architecture-support) table above.

## Updating to a new qBittorrent version

Just re-run `./build.sh` — it always fetches the latest static build and
bakes its version into the QPKG. QNAP's QPKG upgrade mechanism (installing
a newer `.qpkg` over an existing install) preserves the `data/` profile
directory.

## Customizing icons

Drop `YTBqbittorrent.gif` (and optionally `YTBqbittorrent_80.gif`,
`YTBqbittorrent_gray.gif`) into `icons/` before building; `qbuild` only
includes icon files that exist and match `QPKG_NAME`.

## License

The packaging scripts, install/remove hooks, and other original content of
this repository are licensed under the [MIT License](LICENSE).

This project doesn't include or modify qBittorrent source — `build.sh`
downloads a prebuilt static `qbittorrent-nox` binary from
[userdocs/qbittorrent-nox-static](https://github.com/userdocs/qbittorrent-nox-static)
and bundles it unmodified into the `.qpkg`. That binary remains under
qBittorrent's own license: [GPLv2 (or later)](https://github.com/qbittorrent/qBittorrent/blob/master/COPYING),
with a special exception permitting linking against OpenSSL. Corresponding
source is available from the [qBittorrent](https://github.com/qbittorrent/qBittorrent)
and [qbittorrent-nox-static](https://github.com/userdocs/qbittorrent-nox-static)
projects themselves.
