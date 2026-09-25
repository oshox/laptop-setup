# laptop-setup: bootc image for the LG gram 16 (16Z90TS-G.AUG7U1)
#
# Reproduces the package/config state of the source laptop (Fedora Sway
# Atomic 44, managed by rpm-ostree) as a bootc-managed OCI image, minus
# VS Code, Zed, and the mp3-tagging tools. See ../README.md and the plan
# this repo was generated from for the full rationale of every line below.
#
# Build (locally, for testing):
#   openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 \
#     -subj "/CN=oshox laptop kmod signing/" \
#     -keyout /tmp/MOK.priv -outform DER -out secureboot/MOK.der
#   podman build --secret id=mok_privkey,src=/tmp/MOK.priv \
#     -t laptop-setup:local .
#
# In CI this is done with --secret id=mok_privkey,src=<(echo "$MOK_PRIVATE_KEY")
# fed from the MOK_PRIVATE_KEY repo secret. See .github/workflows/build.yml.

FROM quay.io/fedora-ostree-desktops/sway-atomic:44

# --- 1. Repositories -------------------------------------------------------
# RPM Fusion (free + nonfree) and Terra, matching what this laptop has
# layered via rpm-ostree. The Vivaldi repo *file* is copied verbatim from
# the source laptop's /etc/yum.repos.d. (Docker CE's repo is deliberately
# not added — podman/toolbox are the only container runtime on this
# machine; see step 4 below.)
RUN set -eux; \
    FEDORA_VER="$(rpm -E %fedora)"; \
    dnf -y install \
        "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
        "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"; \
    dnf -y install --repofrompath "terra,https://repos.fyralabs.com/terra${FEDORA_VER}" \
        --setopt="terra.gpgkey=https://repos.fyralabs.com/terra${FEDORA_VER}/key.asc" \
        terra-release; \
    dnf clean all

COPY files/etc/yum.repos.d/vivaldi.repo /etc/yum.repos.d/vivaldi.repo

# Same repo priorities as the source laptop (there, set at runtime via
# `dnf config-manager --save --setopt=...`, which is why they show up as
# `priority=` lines inside the .repo files rather than in the repo
# definitions themselves). Also: skip installing docs/man pages for every
# layered package from here on (tsflags=nodocs) — a standard, low-risk
# image-size win (it doesn't touch %license files, only %doc/man/texinfo),
# persisted into /etc/dnf/dnf.conf for the rest of this build.
RUN dnf -y config-manager setopt \
        tsflags=nodocs \
        fedora.priority=1 \
        updates.priority=1 \
        rpmfusion-free.priority=5 \
        rpmfusion-free-updates.priority=5 \
        rpmfusion-nonfree.priority=5 \
        rpmfusion-nonfree-updates.priority=5

# --- 2. ffmpeg-free -> ffmpeg (RPM Fusion) ----------------------------------
# Same swap rpm-ostree performs on the source laptop; removes the same 8
# -free packages (ffmpeg-free, libav{codec,device,filter,format,util}-free,
# libswresample-free, libswscale-free).
RUN dnf -y swap ffmpeg-free ffmpeg --allowerasing && dnf clean all

# --- 3. Power profile daemon: power-profiles-daemon, not tuned-ppd ---------
# The base image (like the source laptop) defaults to tuned + tuned-ppd
# (Fedora's default since F41 — tuned-ppd is a compatibility shim that
# answers the power-profiles-daemon D-Bus API by translating it to tuned
# profiles). For this specific chipset that default is a real, *measured*
# regression, not a style preference: Phoronix benchmarked a Panther Lake
# laptop (same Core Ultra Series 2 generation as this Lunar Lake chip) and
# found Fedora 44 running slower than five other current distros; the fix
# was exactly `dnf swap tuned-ppd power-profiles-daemon` — after that swap
# Fedora matched the others. (https://www.phoronix.com/review/fedora-pantherlake-thermald-tuned)
# thermald and intel_lpmd are left exactly as the base image ships them:
# both already default-enabled, and intel_lpmd has shipped a Lunar-Lake-
# specific config since its 0.0.9 release (Fedora 44 has 0.1.0).
RUN set -eux; \
    dnf -y remove tuned-ppd tuned; \
    dnf -y install power-profiles-daemon; \
    dnf clean all; \
    systemctl enable power-profiles-daemon.service; \
    systemctl mask tuned.service tuned-ppd.service

# --- 4. Packages ---------------------------------------------------------------
# Fedora + updates
#
# Note: kernel-devel/kernel-headers are NOT installed here. They're only
# needed to build the xpadneo kernel module (step 7), never at runtime —
# unlike the source laptop, this image never rebuilds kernel modules on the
# client (a new kernel means a whole new bootc image, built centrally), so
# there's no akmods.service here to keep them around for. Installing and
# removing them within step 7's own RUN instruction, rather than leaving
# them installed here, is what actually keeps them out of the final image:
# an OCI layer's diff is additive, so deleting a file in a *later* layer
# than the one that added it doesn't shrink the image, it just hides the
# bytes. kernel-devel alone is ~240MB on this laptop, kernel-headers ~7MB.
RUN dnf -y install \
        alacritty alsa-lib-devel bat btop cargo clang cmake darktable \
        fontconfig-devel gcc gcc-c++ gimp git glib2-devel \
        gtk-layer-shell-devel gtk3-devel gvfs-mtp \
        libva-devel libxcb-devel libxkbcommon-x11-devel make micro mpv \
        musl-gcc openssl-devel perf perl-File-Compare perl-File-Copy \
        perl-FindBin perl-IPC-Cmd pianobar pip qalculate sqlite-devel strace \
        valgrind wayland-devel \
    && dnf clean all

# Rust/Go/Zig build toolchains, plus dnf-native replacements for the
# Homebrew-only formulae that Fedora now packages itself (see
# migrate/Brewfile for what's left on brew and why). All of these are
# plain Fedora/updates packages — no RPM Fusion or Terra needed:
#   - Rust: `cargo` above already pulls in rustc; rustfmt/clippy/
#     rust-analyzer round out the toolchain (new — the source laptop only
#     has bare cargo+rustc).
#   - Go: `golang` (new — Go isn't installed on the source laptop at all).
#   - Zig: `zig` — replaces the source laptop's manually-installed
#     ~/.local/opt/zig-0.16.0/ binary (dnf's zig is the same 0.16.0).
#     migrate/home-include.txt no longer copies that manual install, so
#     there's no ~/.local/bin/zig shadowing this one on PATH.
#   - helm, k9s, rclone, yq, awscli2 (aws), golang-oras (oras): dnf
#     versions of Brewfile formulae Fedora now ships. `yq` here really is
#     mikefarah/yq (verified — same tool the Brewfile installed, not the
#     unrelated python-yq/jq wrapper some distros ship under that name).
#     golang-oras replaces the source laptop's manually-installed
#     ~/.local/bin/oras the same way zig above does — also dropped from
#     migrate/home-include.txt so it can't shadow this one.
RUN dnf -y install \
        awscli2 clippy golang golang-oras helm k9s rclone rust-analyzer \
        rustfmt yq zig \
    && dnf clean all

# RPM Fusion: VA-API driver for Intel Arc (Lunar Lake iHD)
RUN dnf -y install intel-media-driver && dnf clean all

# Terra: yazi. (akmod-xpadneo is installed, built, and removed again
# entirely within step 7 below — see the note in step 4 above.)
RUN dnf -y install yazi && dnf clean all

# Vivaldi is installed in step 6 below, not here — see that step's note.

# Steam + Deluge as native packages, replacing every flatpak app the source
# laptop had (Steam, Pithos, Obsidian, Deluge, Fedora Media Writer,
# Nicotine+): Steam and Deluge are kept, native; the rest are dropped
# outright, not reinstalled in any form. Deluge is in Fedora's own repos.
# Steam needs RPM Fusion's nonfree-steam repo, which ships disabled by
# default (curated separately from the rest of nonfree) — enabled only for
# this one transaction, not left on at runtime.
RUN dnf -y install deluge \
    && dnf -y --enablerepo=rpmfusion-nonfree-steam install steam \
    && dnf clean all

# Explicitly NOT installed in the final image, per request: `code` (VS
# Code), `zed`, the mp3 taggers (beets is pip-user only on the source
# laptop and is likewise not reinstalled — see migrate/pip-user.txt),
# every flatpak app other than the two above, and Docker CE (docker-ce/
# docker-ce-cli/containerd.io/docker-compose-plugin) — podman/toolbox are
# the only container runtime here, unlike the source laptop which has both
# installed. Separately, kernel-devel/kernel-headers/akmods/kmodtool/
# rpm-build are installed *and removed* in step 7 below, purely as a means
# to build the signed xpadneo module — see the note there.

# --- 5. Nix package manager directory ---------------------------------------
# Only the /nix -> var/nix symlink is set up here, as a permanent part of
# the root tree (the same way this base image already has /opt -> var/opt,
# /srv -> var/srv, etc.) — /var is where an ostree/bootc system keeps state
# that's meant to persist and grow across upgrades untouched, which is
# exactly what a Nix store is. Nix itself is *not* installed at build time:
# unlike Vivaldi (step 6), where the payload is a static, versioned thing
# we deliberately want reset from /usr on every upgrade, a Nix store is
# supposed to accumulate whatever you've installed and survive upgrades
# unchanged — so baking an initial store into the image's /var would only
# ever take effect on the very first deployment anyway (see step 6's note
# on why), and would be actively wrong here since it'd imply resetting it.
# Installing Nix itself is therefore a first-boot, human-run step — see
# README.md's toolchain reinstall list (Determinate Systems installer,
# multi-user/daemon mode, the same one https://nixos.org itself now
# recommends). This also sidesteps trying to run a systemd-managing
# installer inside this build, which has no real PID 1 to talk to.
RUN ln -sf var/nix /nix

# --- 6. Vivaldi, installed into a real /opt then relocated -----------------
# /opt is a symlink to /var/opt in bootc images, and unlike /usr, a fresh
# image's /var content is only applied on the *initial* deployment, not on
# later `bootc upgrade`s. So the real Vivaldi payload needs to end up in
# /usr/lib/opt/vivaldi (part of /usr, which *does* get updated every
# upgrade), with files/usr/lib/tmpfiles.d/vivaldi.conf recreating
# /var/opt/vivaldi -> /usr/lib/opt/vivaldi on every boot. This is what
# rpm-ostree does automatically for /opt content on the source laptop.
#
# The RPM is deliberately *not* installed straight through the existing
# /opt -> var/opt symlink (that was the original approach here, and it's
# what a live rpm-ostree/dnf system would do without a second thought) —
# on GitHub's runners specifically, cpio extracting through that symlink
# during the RPM transaction fails outright ("mkdir failed - No data
# available"), most likely an SELinux-xattr quirk of buildah's storage
# driver on a non-SELinux build host. Swapping in a plain, real /opt
# directory for the duration of the install sidesteps the symlink
# traversal entirely, regardless of the exact cause.
RUN set -eux; \
    rm -f /opt; \
    mkdir -p /opt; \
    dnf -y install vivaldi-stable; \
    dnf clean all; \
    mkdir -p /usr/lib/opt; \
    mv /opt/vivaldi /usr/lib/opt/vivaldi; \
    rm -rf /opt; \
    ln -sf var/opt /opt

# --- 7. Xbox controller driver (akmod-xpadneo), signed for Secure Boot -----
# Everything needed only to *build* the module — kernel-devel, kernel-
# headers, and akmod-xpadneo itself (which pulls in akmods, kmodtool,
# rpm-build, gcc's already-kept anyway) — is installed and removed again
# within this one RUN instruction, so none of it ends up in the image:
# only the already-compiled, already-signed kmod-xpadneo-<kver> package
# and the small xpadneo userspace package (udev rules, modprobe.d config —
# built as a sibling RPM by the same akmods run) persist. That's also the
# right behavior architecturally, not just a size trick: this image never
# rebuilds kernel modules client-side (see step 4's note), so there's no
# ongoing use for the build toolchain after this step.
#
# The private half of the MOK keypair is only ever available inside this
# RUN instruction, via a build secret, and is deleted before the
# instruction ends -- it is never written to an image layer. The public
# cert is baked into the image at /usr/share/laptop-setup/MOK.der so it can
# be enrolled with `mokutil --import` on first boot (see migrate/FIRST-BOOT.md).
COPY secureboot/MOK.der /usr/share/laptop-setup/MOK.der
RUN --mount=type=secret,id=mok_privkey,target=/run/secrets/mok_privkey \
    set -eux; \
    KVER="$(rpm -q kernel-core --qf '%{version}-%{release}.%{arch}\n')"; \
    dnf -y install "kernel-devel-${KVER}" "kernel-headers-${KVER}" akmod-xpadneo; \
    install -D -m0444 /usr/share/laptop-setup/MOK.der /etc/pki/akmods/certs/public_key.der; \
    install -D -m0400 -o root -g akmods /run/secrets/mok_privkey /etc/pki/akmods/private/private_key.priv; \
    chown root:akmods /etc/pki/akmods/certs/public_key.der; \
    chmod 0750 /etc/pki/akmods/certs /etc/pki/akmods/private; \
    akmods --force --kernels "$KVER" --akmod xpadneo; \
    MODULE="$(find "/usr/lib/modules/${KVER}" -iname 'hid_xpadneo.ko*' -print -quit)"; \
    test -n "$MODULE" || { echo "hid_xpadneo module was not built" >&2; exit 1; }; \
    SIGNER="$(modinfo -F signer "$MODULE" 2>/dev/null || true)"; \
    echo "hid_xpadneo module signer: ${SIGNER:-<NONE>}"; \
    test -n "$SIGNER" || { echo "hid_xpadneo module is UNSIGNED" >&2; exit 1; }; \
    rm -f /etc/pki/akmods/private/private_key.priv; \
    dnf -y remove "kernel-devel-${KVER}" "kernel-headers-${KVER}" akmod-xpadneo akmods kmodtool rpm-build rpm-build-libs; \
    dnf clean all; \
    rm -rf /usr/src/akmods/*; \
    rpm -q xpadneo >/dev/null || { echo "xpadneo (udev/modprobe support package) did not survive build-dep cleanup" >&2; exit 1; }; \
    SIGNER2="$(modinfo -F signer "$MODULE" 2>/dev/null || true)"; \
    test "$SIGNER2" = "$SIGNER" || { echo "hid_xpadneo module changed or disappeared after build-dep cleanup" >&2; exit 1; }

# --- 8. authselect -----------------------------------------------------------
# Same feature set as the source laptop, plus with-systemd-homed (needed for
# pam_systemd_home so login/SDDM/swaylock/sudo work with the homed-managed
# encrypted home).
RUN authselect select local with-silent-lastlog with-mdns4 with-fingerprint \
        with-systemd-homed --force

# --- 9. System config files (see files/ for the full tree) -----------------
COPY files/etc/sudoers.d/10-wheel-nopasswd /etc/sudoers.d/10-wheel-nopasswd
COPY files/etc/security/limits.d/nofile.conf /etc/security/limits.d/nofile.conf
COPY files/etc/sddm.conf.d/10-custom-theme.conf /etc/sddm.conf.d/10-custom-theme.conf
COPY files/etc/firewalld/zones/public.xml /etc/firewalld/zones/public.xml
COPY files/etc/firewalld/zones/trusted.xml /etc/firewalld/zones/trusted.xml
COPY files/usr/lib/systemd/logind.conf.d/10-lid.conf /usr/lib/systemd/logind.conf.d/10-lid.conf
COPY files/usr/lib/systemd/system/user@.service.d/delegate.conf /usr/lib/systemd/system/user@.service.d/delegate.conf
COPY files/usr/lib/tmpfiles.d/vivaldi.conf /usr/lib/tmpfiles.d/vivaldi.conf
COPY files/usr/share/sddm/themes/custom-theme /usr/share/sddm/themes/custom-theme

RUN chmod 0440 /etc/sudoers.d/10-wheel-nopasswd && visudo -c

# --- 10. Services ------------------------------------------------------------
# power-profiles-daemon is already enabled (step 3); tuned/tuned-ppd
# already masked there too. Docker CE isn't installed at all here, so
# there's no docker/containerd unit to leave disabled, unlike the source
# laptop. bootc-fetch-apply-updates.timer stays disabled too — the source
# laptop's rpm-ostree AutomaticUpdatePolicy is "stage" but its timer is
# inactive, so updates there are effectively manual already (`bootc
# upgrade` here). Base-image defaults (flatpak-add-fedora-repos.service
# etc.) are untouched.

# --- 11. Validate ------------------------------------------------------------
RUN bootc container lint
