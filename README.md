# Mirishita Waydroid Installer (MWI)

MWI bootstraps a fresh Waydroid Android 11 environment with Google Play on supported x86_64 Linux PCs with AMD Radeon graphics. It installs the host prerequisites, a pinned Android 11 + GApps image, Houdini through the third-party `waydroid_script` project, MWI's patched `test_libnb`, and Waydroid network setup.

MWI does **not** include, request, download, or install the Mirishita game APK. After setup, sign in to Google Play and install the game yourself.

## v0.1.0 support

- CachyOS and Arch Linux
- Regular dnf-based Fedora editions, including Workstation and KDE Plasma Desktop
- x86_64 host, AMD Radeon GPU using `amdgpu`, DRM render node, and a Wayland desktop session
- Fresh Waydroid installation only

Ubuntu is planned. Intel-only, NVIDIA-only, and Fedora Atomic/Silverblue/Kinoite systems are not supported by this release. Wayland is required by the intended setup; other sessions are not validated.

This is an early release. The packaged script and binary payload receive static checks in this repository; a fresh install on every supported distribution has not been independently re-run for v0.1.0. Review [known limitations](docs/SETUP.md#known-limitations) before installing.

## Install

On a supported Linux desktop, open a terminal and run:

```bash
git clone https://github.com/relorah/mirishita-waydroid-installer.git
cd mirishita-waydroid-installer
chmod +x install.sh
./install.sh
```

Run as your regular desktop user. The installer asks `sudo` for administrative actions. It intentionally stops if an existing Waydroid installation is detected; it will not reset or delete existing Waydroid data.

The setup downloads about 1.1 GB of Android images plus Houdini components at runtime. A stable internet connection and several GB of free disk space are required. Follow the first-run Google Play setup in Waydroid, then install Mirishita from Google Play.

See [Setup and recovery notes](docs/SETUP.md) for the full flow, verification, and troubleshooting. Japanese instructions are available in [docs/SETUP_JA.md](docs/SETUP_JA.md).

## What the installer changes

- Installs Waydroid and host packages with `pacman` or `dnf`.
- Downloads fixed Waydroid system/vendor archive filenames from SourceForge, validates ZIP integrity and expected image members, and installs them under `/etc/waydroid-extra/images`.
- Runs `waydroid init -f` and checks Android 11 and Google Play availability.
- Downloads the `casualsnek/waydroid_script` source archive at the commit recorded in `install.sh`, creates a local Python virtual environment, and asks that project to install Android 11 `libhoudini`.
- Copies the bundled 32-bit and 64-bit `libnb.so` files into Waydroid's system overlay, applies the required NativeBridge properties, and checks ARM64 ABI exposure.
- Enables IPv4 forwarding and adds the Waydroid interface to an active UFW/firewalld configuration where applicable.
- Starts the Waydroid UI and requests Google Play launch.

The installer does not configure MWM display, touch, resolution, frame-rate, or performance features. MWI prepares the base Waydroid environment; MWM is a separate runtime/display/performance manager.

## Reproducibility and verification

- Android images are pinned by their published filenames and source URLs in `install.sh`; the script checks archive integrity and expected members. SourceForge does not publish a checksum in the directory listing used for these files, so MWI does not claim cryptographic authenticity for those downloads.
- `waydroid_script` is pinned to commit `48dbfaf34a6ddbe78688c530f9ba1c26522aafb2`.
- `test_libnb` binaries are checked against SHA-256 values embedded in `install.sh` and listed in [`test_libnb/SHA256SUMS`](test_libnb/SHA256SUMS).
- Houdini binaries are never included in this repository. The installer delegates their retrieval and setup to `casualsnek/waydroid_script` at runtime. This separation describes MWI's packaging; it is not a legal conclusion about third-party licensing or use.

## Repository contents

```text
install.sh                 Installer
docs/                      Setup, recovery, and licensing notes
test_libnb/                 MWI source, build script, and required ELF payloads
LICENSE                    License for MWI-authored installer and documentation
NOTICE                     Third-party attribution and scope
LICENSES/                  License texts for included third-party code
```

The `test_libnb` directory contains the complete corresponding source and build script for the bundled binaries. See [licensing notes](docs/LICENSING.md) and [`NOTICE`](NOTICE).

## Disclaimer

Waydroid, LineageOS, Google Play, Houdini, Mirishita, and the named distributions are third-party products and marks. MWI is an independent community project and is not affiliated with or endorsed by their respective owners. Users are responsible for following the terms that apply to software and services they obtain or use.
