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
# layered via rpm-ostree. Vivaldi and Docker CE repo *files* are copied
# verbatim from the source laptop's /etc/yum.repos.d.
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
COPY files/etc/yum.repos.d/docker-ce.repo /etc/yum.repos.d/docker-ce.repo

# Same repo priorities as the source laptop (there, set at runtime via
# `dnf config-manager --save --setopt=...`, which is why they show up as
# `priority=` lines inside the .repo files rather than in the repo
# definitions themselves).
RUN dnf -y config-manager setopt \
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
RUN dnf -y swap ffmpeg-free ffmpeg --allowerasing

# --- 3. Packages -------------------------------------------------------------
# Fedora + updates
#
# kernel-devel/kernel-headers are pinned to the *already-installed*
# kernel-core version (i.e. the kernel actually baked into this base
# image), not left to float to whatever's newest in the repos — otherwise
# an unpinned `dnf install kernel-devel` could resolve to a newer kernel
# than the one this image boots, and the xpadneo module built in step 5
# would silently target the wrong /usr/lib/modules/<version> tree.
RUN set -eux; \
    KVER="$(rpm -q kernel-core --qf '%{version}-%{release}.%{arch}\n')"; \
    dnf -y install \
        alacritty alsa-lib-devel bat btop cargo clang cmake darktable \
        fontconfig-devel gcc gcc-c++ gimp git glib2-devel \
        gtk-layer-shell-devel gtk3-devel gvfs-mtp \
        "kernel-devel-${KVER}" "kernel-headers-${KVER}" \
        libva-devel libxcb-devel libxkbcommon-x11-devel make micro mpv \
        musl-gcc openssl-devel perf perl-File-Compare perl-File-Copy \
        perl-FindBin perl-IPC-Cmd pianobar pip qalculate sqlite-devel strace \
        valgrind wayland-devel; \
    dnf clean all

# RPM Fusion: VA-API driver for Intel Arc (Lunar Lake iHD)
RUN dnf -y install intel-media-driver && dnf clean all

# Terra: yazi + the xpadneo akmod source (built and signed in step 5 below)
RUN dnf -y install yazi akmod-xpadneo && dnf clean all

# Vivaldi (see step 4 for the /opt relocation this needs)
RUN dnf -y install vivaldi-stable && dnf clean all

# Docker CE (installed, same as the source laptop, but left disabled —
# podman/toolbox remain the enabled container runtime; see step 6)
RUN dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin \
    && dnf clean all

# Explicitly NOT installed here, per request: `code` (VS Code), `zed`, and
# the mp3 taggers (beets is pip-user only on the source laptop and is
# likewise not reinstalled — see migrate/pip-user.txt).

# --- 4. Vivaldi /opt relocation --------------------------------------------
# /opt is a symlink to /var/opt in bootc images, and unlike /usr, a fresh
# image's /var content is only applied on the *initial* deployment, not on
# later `bootc upgrade`s. So the real Vivaldi payload is moved into
# /usr/lib/opt/vivaldi (part of /usr, which *does* get updated every
# upgrade) and files/usr/lib/tmpfiles.d/vivaldi.conf recreates
# /var/opt/vivaldi -> /usr/lib/opt/vivaldi on every boot. This is what
# rpm-ostree does automatically for /opt content on the source laptop.
RUN set -eux; \
    mkdir -p /usr/lib/opt; \
    mv /opt/vivaldi /usr/lib/opt/vivaldi; \
    rmdir /var/opt/vivaldi 2>/dev/null || true

# --- 5. Xbox controller driver (akmod-xpadneo), signed for Secure Boot -----
# The private half of the MOK keypair is only ever available inside this
# RUN instruction, via a build secret, and is deleted before the
# instruction ends -- it is never written to an image layer. The public
# cert is baked into the image at /usr/share/laptop-setup/MOK.der so it can
# be enrolled with `mokutil --import` on first boot (see migrate/FIRST-BOOT.md).
COPY secureboot/MOK.der /usr/share/laptop-setup/MOK.der
RUN --mount=type=secret,id=mok_privkey,target=/run/secrets/mok_privkey \
    set -eux; \
    install -D -m0444 /usr/share/laptop-setup/MOK.der /etc/pki/akmods/certs/public_key.der; \
    install -D -m0400 -o root -g akmods /run/secrets/mok_privkey /etc/pki/akmods/private/private_key.priv; \
    chown root:akmods /etc/pki/akmods/certs/public_key.der; \
    chmod 0750 /etc/pki/akmods/certs /etc/pki/akmods/private; \
    KVER="$(rpm -q kernel-core --qf '%{version}-%{release}.%{arch}\n')"; \
    akmods --force --kernels "$KVER" --akmod xpadneo; \
    MODULE="$(find "/usr/lib/modules/${KVER}" -iname 'hid_xpadneo.ko*' -print -quit)"; \
    test -n "$MODULE" || { echo "hid_xpadneo module was not built" >&2; exit 1; }; \
    SIGNER="$(modinfo -F signer "$MODULE" 2>/dev/null || true)"; \
    echo "hid_xpadneo module signer: ${SIGNER:-<NONE>}"; \
    test -n "$SIGNER" || { echo "hid_xpadneo module is UNSIGNED" >&2; exit 1; }; \
    rm -f /etc/pki/akmods/private/private_key.priv

# --- 6. authselect -----------------------------------------------------------
# Same feature set as the source laptop, plus with-systemd-homed (needed for
# pam_systemd_home so login/SDDM/swaylock/sudo work with the homed-managed
# encrypted home).
RUN authselect select local with-silent-lastlog with-mdns4 with-fingerprint \
        with-systemd-homed --force

# --- 7. System config files (see files/ for the full tree) -----------------
COPY files/etc/sudoers.d/10-wheel-nopasswd /etc/sudoers.d/10-wheel-nopasswd
COPY files/etc/security/limits.d/nofile.conf /etc/security/limits.d/nofile.conf
COPY files/etc/sddm.conf.d/10-custom-theme.conf /etc/sddm.conf.d/10-custom-theme.conf
COPY files/etc/firewalld/zones/public.xml /etc/firewalld/zones/public.xml
COPY files/etc/firewalld/zones/trusted.xml /etc/firewalld/zones/trusted.xml
COPY files/usr/lib/systemd/logind.conf.d/10-lid.conf /usr/lib/systemd/logind.conf.d/10-lid.conf
COPY files/usr/lib/systemd/system/user@.service.d/delegate.conf /usr/lib/systemd/system/user@.service.d/delegate.conf
COPY files/usr/lib/systemd/system/flatpak-add-flathub.service /usr/lib/systemd/system/flatpak-add-flathub.service
COPY files/usr/lib/systemd/system/flatpak-preinstall.service /usr/lib/systemd/system/flatpak-preinstall.service
COPY files/usr/lib/tmpfiles.d/vivaldi.conf /usr/lib/tmpfiles.d/vivaldi.conf
COPY files/usr/share/flatpak/preinstall.d/laptop.preinstall /usr/share/flatpak/preinstall.d/laptop.preinstall
COPY files/usr/share/sddm/themes/custom-theme /usr/share/sddm/themes/custom-theme

RUN chmod 0440 /etc/sudoers.d/10-wheel-nopasswd && visudo -c

# --- 8. Services -------------------------------------------------------------
# docker/containerd stay disabled, same as the source laptop.
# bootc-fetch-apply-updates.timer stays disabled too: the source laptop's
# rpm-ostree AutomaticUpdatePolicy is "stage" but its timer is inactive, so
# updates there are effectively manual already (`bootc upgrade` here).
RUN systemctl enable flatpak-add-flathub.service flatpak-preinstall.service

# --- 9. Validate -------------------------------------------------------------
RUN bootc container lint
