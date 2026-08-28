# qbittorrent-qpkg

A QNAP QPKG that packages [qBittorrent](https://www.qbittorrent.org/) (headless
`qbittorrent-nox` + WebUI) for QNAP NAS. Built for x86_64 models (e.g. the
TS-251B).

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
x86_64/            # architecture-specific files, x86_64 only
  qbittorrent-nox  # fetched by build.sh, not committed
icons/             # optional App Center icons (qbittorrent[.gif|_80.gif|_gray.gif])
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
2. Download the latest `x86_64-qbittorrent-nox` static binary.
3. Run `qbuild` to produce `build/qbittorrent_<version>_x86_64.qpkg`.

Requires `git`, `curl`, and a C compiler (`cc`/`gcc`) on the build machine.
Nothing QNAP-specific is required to build — `qbuild` is a portable shell
script.

### Signing a release

Releases are GPG-signed with key `A89A45D89CADF434` (public key committed as
[`qbittorrent-qpkg-release-key.asc`](qbittorrent-qpkg-release-key.asc)). To
sign while building, set `QPKG_GPG_KEY` to a key ID you hold the secret key
for:

```
QPKG_GPG_KEY=A89A45D89CADF434 ./build.sh
```

This produces two things in `build/` beyond the `.qpkg` itself:
- The signature embedded *inside* the `.qpkg` by QDK's own `--sign`,
  checkable with `qbuild --verify build/qbittorrent_<version>_x86_64.qpkg`.
- A standalone detached signature, `qbittorrent_<version>_x86_64.qpkg.asc`,
  checkable with plain `gpg` — no QDK required. This is the one to publish
  alongside the `.qpkg` for others to verify:

  ```
  gpg --import qbittorrent-qpkg-release-key.asc
  gpg --verify qbittorrent_<version>_x86_64.qpkg.asc qbittorrent_<version>_x86_64.qpkg
  ```

Leaving `QPKG_GPG_KEY` unset (the default) skips signing entirely, so the
build still works for anyone without the private key.

## Installing

In QTS: **App Center → (⚙️ gear icon, top right) → Install Manually**, then
browse to the `.qpkg` file from `build/`.

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
  `/share/<volume>/.qpkg/qbittorrent/data/qbittorrent-nox.log` (look for a
  line starting "The WebUI administrator password was not set..."). Change
  it immediately under WebUI → Options → Web UI — note the password is
  visible in plaintext to anyone who can read the System Event Log (i.e.
  any NAS admin), same as it already was in the log file.
- **Data location**: qBittorrent's profile (settings, resume data, and its
  *default* download save path) lives under
  `<install path>/qbittorrent/data/`. **Uninstalling the package deletes
  this directory**, including any torrents saved to the default path. Set
  a save path on one of your data volumes (e.g. `/share/Download`) under
  WebUI → Options → Downloads before adding torrents, if you want it to
  survive an uninstall/reinstall.
- **Architecture**: this package only ships x86_64 binaries. It will refuse
  to install on ARM-based QNAP models.

## Updating to a new qBittorrent version

Just re-run `./build.sh` — it always fetches the latest static build and
bakes its version into the QPKG. QNAP's QPKG upgrade mechanism (installing
a newer `.qpkg` over an existing install) preserves the `data/` profile
directory.

## Customizing icons

Drop `qbittorrent.gif` (and optionally `qbittorrent_80.gif`,
`qbittorrent_gray.gif`) into `icons/` before building; `qbuild` only
includes icon files that exist and match the package name.
