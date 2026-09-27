# Echo 0.1.1

This maintenance release adds a Debian/Ubuntu installer and improves Linux desktop integration and release metadata. Echo is provided for 64-bit x86 Linux.

## Changes

- Adds a Debian/Ubuntu `.deb` installer alongside the portable Linux archive.
- Corrects the Linux application identity and desktop window class so the Echo icon is associated with the running app.
- Adds one best-effort, anonymous first-launch install-count report. A local flag prevents ordinary later launches from reporting again.
- Records the author, maintainer, and proprietary rights notice in the project and package metadata.

## Downloads

- `echo_0.1.1_amd64.deb` — install with `sudo apt install ./echo_0.1.1_amd64.deb`.
- `Echo-linux-x86_64.tar.gz` — extract the archive and run `bundle/echo`.

The Debian package installs the app under `/opt/echo` and adds an application menu entry. The portable archive does not install menu shortcuts.

## Install-count privacy

On first launch for a local app data installation, Echo sends an empty-body POST to its install-count endpoint. It sends no name, email address, device identifier, or analytics payload. The report counts accepted first-launch requests, not verified downloads, unique people, or unique devices. If Echo is offline or the endpoint is unavailable on that first launch, the report may be missed. The hosting provider processes connection metadata, including the source IP address.

## Author and license

Author and maintainer: Manasseh Sasu <apptechsolutions352@gmail.com>.

Proprietary. All rights reserved.

## SHA-256 checksums

```text
eac866b6514af191f19a84cb27bdc1c9efa3d5fc89b01354708063d39f9cc7f0  Echo-linux-x86_64.tar.gz
92e8c0577ce3825256b199fd32ca007dec5d8c48d238b97276ca9c5becc96ce5  echo_0.1.1_amd64.deb
```
