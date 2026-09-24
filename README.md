# laptop-setup

Clones the setup of the source Fedora Sway Atomic 44 laptop onto the LG
gram 16 (16Z90TS-G.AUG7U1), as a **bootc**-managed image instead of
rpm-ostree. Full rationale for every customization is in the plan this repo
was generated from; the short version:

- **No full-disk encryption.** Only the home directory is encrypted
  (systemd-homed, LUKS2), stored on the laptop's **second** SSD.
- **Autologin disabled.**
- **Not installed:** VS Code, Zed, and the mp3-tagging tools
  (puddletag, MusicBrainz Picard, beets).
- **Steam and Deluge as native RPMs**, not flatpaks. Every other flatpak
  app the source laptop had (Pithos, Obsidian, Fedora Media Writer,
  Nicotine+) is dropped, not reinstalled in any form — so no flatpak apps
  are preinstalled at all.
- **No Docker CE.** The source laptop has both docker-ce and podman
  installed (docker unused, left disabled); this image has podman/toolbox
  only.

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
   it automatically). Plug in wired Ethernet (USB-C adapter).
3. Boot the installer, confirm disk names first (`ks.cfg`'s header
   explains how), then let it run. It stops to ask for a **temporary root
   password** — there's no kickstart `user`/`rootpw` on purpose.
4. Follow `migrate/FIRST-BOOT.md`.
5. Migrate home configs:
   ```
   # on the old laptop: sudo systemctl start sshd   (stop it again after)
   rsync -aHr --files-from=migrate/home-include.txt oshox@old-laptop.local:/var/home/oshox/ ~/
   sudo restorecon -R ~
   ./migrate/adjust-dotfiles.sh
   ```
6. Reinstall the user-level toolchains:
   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew bundle --file=migrate/Brewfile
   curl -fsSL https://get.pnpm.io/install.sh | sh -
   pnpm add -g $(cat migrate/pnpm-globals.txt)
   pip install --user -r migrate/pip-user.txt
   # Claude Code: native installer, https://claude.com/claude-code
   ```
7. Copy over anything from "credentials, not copied by the rsync above"
   (see the plan's §D4) by hand: `~/.ssh ~/.aws ~/.kube`, VPN configs, the
   GitHub PAT, etc. — deliberately not synced automatically.

## Updating

```
sudo bootc upgrade --check   # see what's new
sudo bootc upgrade && sudo systemctl reboot
```

Nothing runs this automatically (`bootc-fetch-apply-updates.timer` stays
disabled) — matching the source laptop, where the rpm-ostree auto-update
timer was likewise inactive.

## Rebuilding locally (for testing changes to this repo)

```
openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 \
    -subj "/CN=test/" -keyout /tmp/MOK.priv -outform DER -out /tmp/MOK-test.der
cp /tmp/MOK-test.der secureboot/MOK.der   # don't commit this test cert
podman build --secret id=mok_privkey,src=/tmp/MOK.priv -t laptop-setup:local .
git checkout secureboot/MOK.der           # restore the real public cert
```
