# laptop-setup

Clones the setup of the source Fedora Sway Atomic 44 laptop onto the LG
gram 16 (16Z90TS-G.AUG7U1), as a **bootc**-managed image instead of
rpm-ostree. Full rationale for every customization is in the plan this repo
was generated from; the short version:

- **No full-disk encryption.** Only the home directory is encrypted
  (systemd-homed, LUKS2), stored on the laptop's **second** SSD.
- **Autologin disabled.**
- **swayfx instead of stock sway** (Terra). A drop-in fork — same
  `/usr/bin/sway`, same keybindings, same `sway-config-fedora`/
  `sddm-wayland-sway`/`sway-systemd` integration — that adds rounded
  corners, background blur, drop shadows, dim-inactive, and window
  animations. The effect settings themselves live in the user's
  `~/.config/sway/config` (see `migrate/home-include.txt`), not in this
  repo; only the package swap is here.
- **Not installed:** VS Code, Zed, and the mp3-tagging tools
  (puddletag, MusicBrainz Picard, beets).
- **Steam and Deluge as native RPMs**, not flatpaks. Every other flatpak
  app the source laptop had (Pithos, Obsidian, Fedora Media Writer,
  Nicotine+) is dropped, not reinstalled in any form — so no flatpak apps
  are preinstalled at all.
- **gamescope, protonplus, and lutris**, also native RPMs (Fedora's own
  repo, Terra, and Fedora's own repo again, respectively), for Steam Play
  and Lutris both. protonplus only installs the GE-Proton *manager*; run
  it once at first login to actually fetch a GE-Proton build into
  `~/.local/share/Steam/compatibilitytools.d` — that download is per-user
  data on the second SSD, not baked into the image. Lutris needs no extra
  wiring to use either of the other two: it shows a "Use Gamescope"
  toggle per game whenever `gamescope` is on PATH, and it scans
  `~/.local/share/Steam/compatibilitytools.d` itself for GE-Proton/Wine-GE
  builds to offer as Wine/Proton runners, so whatever protonplus fetches
  there is picked up automatically.
- **No Docker CE.** The source laptop has both docker-ce and podman
  installed (docker unused, left disabled); this image has podman/toolbox
  only.
- **Rust, Go, and Zig build toolchains**, and dnf in place of Homebrew
  wherever Fedora packages the same tool (verified against real Fedora 44
  repo metadata — see the Containerfile's "Rust/Go/Zig build toolchains"
  step and `migrate/Brewfile`).
- **Image size optimized:** doc/man pages skipped for every layered
  package, and the ~250MB of kernel-devel/headers (plus akmods/kmodtool/
  rpm-build) needed only to build the xpadneo module never persist in the
  image — installed and removed within the same layer. The base image
  itself is unchanged: `sway-atomic` is already Fedora's lightweight
  Sway-based bootc desktop, and there's no smaller variant that's still a
  real Sway desktop.
- **power-profiles-daemon instead of tuned/tuned-ppd.** Fedora's own
  default since F41 is measurably worse on this chip's generation —
  Phoronix benchmarked a Panther Lake laptop (same Core Ultra Series 2
  family as this Lunar Lake chip) running slower than five other distros
  on Fedora 44, and `dnf swap tuned-ppd power-profiles-daemon` was the
  fix. thermald and intel_lpmd are untouched (already enabled by the base
  image, and intel_lpmd has shipped Lunar-Lake-specific config since
  v0.0.9 — Fedora 44 has 0.1.0).
- **Nix added** (Determinate Systems installer, multi-user/daemon mode).
  Only an empty `/nix` mountpoint is baked into the image (the store lives
  in `/var/home/nix`, bind-mounted onto it); Nix itself installs at first
  login (see "Migrating your home directory" below) —
  a Nix store is meant to grow and persist across upgrades untouched, so
  installing it live is the architecturally correct choice here, not just
  the easy one.

## Layout

| Path | What |
|---|---|
| `Containerfile` | The image. Everything system-level is here or in `files/`. |
| `files/` | Files copied verbatim into the image — audit these directly. |
| `secureboot/MOK.der` | Public half of the kernel-module signing key (safe to commit). The private half is **never** in this repo — see below. |
| `.github/workflows/build.yml` | Builds and pushes `ghcr.io/oshox/laptop-setup:latest` on push/nightly/manual. |
| `install/ks.cfg` | Kickstart for the Fedora 44 Everything netinstall ISO. **Wipes both SSDs.** |
| `migrate/FIRST-BOOT.md` | Manual steps right after install (create the homed user, enroll MOK, etc). |
| `migrate/home-include.txt` | Exact file list rsync'd from the old laptop's home directory. |
| `migrate/adjust-dotfiles.sh` | The handful of dotfile edits needed for the new hardware (run after the rsync). |
| `migrate/Brewfile`, `pnpm-globals.txt`, `pip-user.txt` | Reinstalled (not copied) user-level toolchains. |

## The MOK signing key

Secure Boot stays on, and the akmod-xpadneo (Xbox controller) kernel module
is self-signed so it can load. The keypair was generated once with:

```
openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 \
    -subj "/CN=oshox laptop kmod signing/" \
    -keyout MOK.priv -outform DER -out secureboot/MOK.der
```

- `secureboot/MOK.der` (public) is committed here and baked into the image.
- `MOK.priv` (private) is **not** in this repo (see `.gitignore`). It must
  be stored somewhere durable — a password manager — and set as the
  `MOK_PRIVATE_KEY` GitHub Actions repo secret (Settings → Secrets and
  variables → Actions). CI passes it to `podman build --secret` for the one
  `RUN` step that signs the module, and deletes it before that step ends —
  it never lands in an image layer.

## One-time setup before the first real build

1. Create the GitHub repo (private is fine) and push this directory to it.
2. Add the `MOK_PRIVATE_KEY` repo secret (see above).
3. Push to `main` / run the workflow manually once.
4. On github.com under your account's Packages, open `laptop-setup` →
   Package settings → change visibility to **Public**. The repo can stay
   private; the *image* holds no secrets, and a public image means the new
   laptop needs no registry credentials to install or to `bootc upgrade`.

## Installing on the new laptop

1. In Windows, install any pending LG BIOS/firmware updates (LG Update).
2. Write a Fedora 44 Everything netinstall ISO to a USB stick, and
   `install/ks.cfg` to a second USB stick labeled `OEMDRV` (Anaconda loads
   it automatically).
3. Boot the installer, confirm disk names first (`ks.cfg`'s header
   explains how). It stops at the Installation Summary screen with two
   spokes flagged as needing attention, since the kickstart deliberately
   leaves both unset: **Network & Host Name** — connect to Wi-Fi there
   (no Ethernet adapter needed; see `ks.cfg`'s networking note for why
   Wi-Fi can't be scripted into the kickstart itself) — and **Root
   Account** — set a **temporary** password (there's no kickstart
   `user`/`rootpw` on purpose). Configure both, then click "Begin
   Installation".
4. Follow `migrate/FIRST-BOOT.md`.
5. Migrate home configs:
   ```
   # on the old laptop: sudo systemctl start sshd   (stop it again after)
   rsync -aHr --files-from=<(grep -v '^#' migrate/home-include.txt) oshox@old-laptop.local:/var/home/oshox/ ~/
   sudo restorecon -R ~
   ./migrate/adjust-dotfiles.sh
   ```
6. Reinstall the user-level toolchains:
   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew bundle --file=migrate/Brewfile
   curl -fsSL https://get.pnpm.io/install.sh | sh -
   pnpm add -g $(grep -v '^#' migrate/pnpm-globals.txt)
   pip install --user -r migrate/pip-user.txt
   curl -fsSL https://claude.ai/install.sh | bash          # Claude Code CLI
   curl -fsSL https://install.determinate.systems/nix | sh -s -- install   # Nix, multi-user/daemon mode
   ```
   Nix's installer starts `nix-daemon` via systemd itself — no reboot
   needed — but `nix` won't be on `$PATH` until a new shell (or
   `. /etc/profile.d/nix.sh`). It detects the ostree system and writes a
   `nix.mount` unit bind-mounting `/var/home/nix` onto the image's empty
   `/nix` directory.
7. Copy over anything from "credentials, not copied by the rsync above"
   (see the plan's §D4) by hand: `~/.ssh ~/.aws ~/.kube`, VPN configs, the
   GitHub PAT, etc. — deliberately not synced automatically.

**Claude Desktop:** not installed. Anthropic's official Linux beta
(claude.com/download) currently supports only Ubuntu/Debian via apt or a
`.deb` — Fedora and RHEL are explicitly not supported yet. There's a
well-known community repackaging
([aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian))
that unpacks the official `.deb` and rebuilds it for other distros, but
that's a third party repackaging a proprietary Electron app, not something
to bake into this image without you explicitly asking for it. Claude Code
(the CLI, above) covers the same account/functionality on Fedora today.

## bitmagnet + prowlarr (on demand)

Nothing here starts at login. One user unit brings the whole stack up and
down:

```
systemctl --user start media-search   # deluge + pod (postgres, bitmagnet, prowlarr) + wiring
systemctl --user stop media-search    # tears it all down
```

- Bitmagnet, its postgres and Prowlarr run as a rootless podman pod
  (quadlet files in `/etc/containers/systemd/users/`); data lives in named
  podman volumes in your home. Web UIs: bitmagnet <http://localhost:3333>,
  Prowlarr <http://localhost:9696> (loopback only, no login).
- On start, `media-search-provision` registers bitmagnet in Prowlarr as a
  Torznab indexer (`http://localhost:3333/torznab`) and Deluge as a download
  client (`host.containers.internal:8112`). It's idempotent; delete an entry
  in Prowlarr and the next start re-adds it. Set `DELUGE_PASSWORD` in
  `~/.config/media-search.env` if you changed deluge-web's default password
  (`deluge`).
- Deluge runs headless for this (`deluge-daemon` + `deluge-web` user
  services, started and stopped with the stack). Don't use the Deluge GUI in
  thin-client mode against it at the same time as classic mode.
- Bitmagnet's DHT crawler uses port 3334 tcp/udp (opened in the public
  firewalld zone). Expect the first results after it's been running a while.

## Updating

`bootc-stage-updates.timer` runs weekly and stages whatever CI has most
recently pushed to `ghcr.io/oshox/laptop-setup:latest` — it does not apply
it. Nothing reboots on its own; the staged update takes effect at whatever
reboot you next do (`sudo systemctl reboot`).

```
systemctl list-timers bootc-stage-updates.timer   # see when it'll next run
sudo systemctl start bootc-stage-updates.service  # trigger a check now
journalctl -u bootc-stage-updates                 # see what it did
sudo bootc status                                 # staged vs booted deployment
```

You can also drive it by hand instead, exactly as the timer does:

```
sudo bootc upgrade --check   # see what's new, without staging it
sudo bootc upgrade && sudo systemctl reboot
```

If a staged update turns out to be bad after rebooting into it,
`sudo bootc rollback && sudo systemctl reboot` goes back to the previous
deployment.

## Rebuilding locally (for testing changes to this repo)

```
openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 \
    -subj "/CN=test/" -keyout /tmp/MOK.priv -outform DER -out /tmp/MOK-test.der
cp /tmp/MOK-test.der secureboot/MOK.der   # don't commit this test cert
podman build --secret id=mok_privkey,src=/tmp/MOK.priv -t laptop-setup:local .
git checkout secureboot/MOK.der           # restore the real public cert
```
