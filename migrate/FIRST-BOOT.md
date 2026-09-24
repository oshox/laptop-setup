# First boot (manual, run once as root on a TTY)

After the kickstart install finishes and the machine reboots, SDDM will
show a login screen with no users yet.

1. Press **Ctrl+Alt+F3** to get a text console, and log in as `root` with
   the temporary password you set during install.

2. Confirm the home partition and fix a known SELinux labeling gap that
   otherwise breaks systemd-homed on Fedora Atomic images:

   ```
   findmnt /var/home          # should show the ext4 partition on nvme1n1
   restorecon -Rv /var/cache/systemd/home
   ```

3. Create the encrypted-home user. This prompts you for a password —
   that password both logs you in and unlocks the home directory:

   ```
   homectl create oshox --uid=1000 --member-of=wheel \
       --storage=luks --fs-type=btrfs --shell=/bin/bash
   ```

   - The encrypted image file is `/var/home/oshox.home`, on SSD 2 (nvme1n1).
     It's sized at 85% of free space by default and auto-grows/shrinks.
   - `--uid=1000` matters: `.bashrc.d/docker-compat.bashrc` hardcodes
     `/run/user/1000/...`, and the subuid/subgid ranges set by the
     kickstart's `%post` assume UID 1000 too.

4. Lock the temporary root account, then switch back to the graphical
   session and log in as `oshox`:

   ```
   passwd -l root
   ```

   Press **Ctrl+Alt+F1** (or F2) to get back to SDDM.

5. Enroll the xpadneo kernel module signing key with MOK (Secure Boot is
   kept on for this machine):

   ```
   sudo mokutil --import /usr/share/laptop-setup/MOK.der
   ```

   You'll be asked to set a one-time enrollment password. Reboot; on the
   blue "MOK Management" screen choose **Enroll MOK → Continue → Yes**,
   enter that password (the keyboard is QWERTY-mapped regardless of your
   normal layout), then let it reboot again.

   Verify afterwards: `mokutil --list-enrolled` should show the cert, and
   `modinfo hid_xpadneo | grep signer` should be non-empty once a
   controller is paired and the module loads.

6. Copy the two `/usr/local`-installed binaries from the source laptop
   (they aren't packaged, just copied):

   ```
   scp old-laptop.local:/var/usrlocal/bin/{eksctl,k0s} /usr/local/bin/
   sudo restorecon -v /usr/local/bin/eksctl /usr/local/bin/k0s
   ```

Next: run the home-directory migration (see `../README.md` "Migrating your
home directory").
