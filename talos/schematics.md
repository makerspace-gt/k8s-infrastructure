# Talos Image Factory schematics

Registry of the Image Factory schematic IDs used in this repo, with the inputs
that produce them so any can be regenerated at <https://factory.talos.dev>.
A schematic ID is a hash of its customization (system extensions + kernel args);
it does **not** encode the Talos version, which is the image tag (`:v1.13.3`).

To change kernel args on an already-installed node, generate a new schematic and
`talosctl upgrade --image factory.talos.dev/metal-installer/<id>:<version>` — the
UKI embeds the cmdline, so `machine.install.extraKernelArgs` is ignored on v1.10+.

## `cc6abef19f4a24ca6c2fdf9e51fbc66a5c43350670f0660c77a6909d0c0c6479` — install (current)

Referenced by all three `controlplane*-patch.yaml` files. All three nodes run this
schematic.

- **Factory:** <https://factory.talos.dev/?arch=amd64&platform=metal&schematic-id=cc6abef19f4a24ca6c2fdf9e51fbc66a5c43350670f0660c77a6909d0c0c6479&secureboot=undefined&target=metal&version=1.13.3>
- **System extensions:** `siderolabs/iscsi-tools`, `siderolabs/util-linux-tools`
  (Longhorn), `siderolabs/nfs-utils` (RWX), `siderolabs/intel-ucode`,
  `siderolabs/amd-ucode`
- **Extra kernel args:** `-console console=tty0`

## `c46052e8f4622594a340274cf198b7af1a771bdc15a268669f97826fc8f8b813` — USB-ethernet test (REVERTED 2026-06-15)

Temporary experiment, now **rolled back** — laptopcp03 was live-upgraded to this schematic
and reverted to `cc6abef…` on 2026-06-15 (the usbcore args did not fix descriptor read).
Kept here so the experiment isn't repeated.

It added usbcore enumeration args to test whether the bare UGREEN RTL8153 adapters could
complete descriptor read on the laptop's xHCI (they fail at `GET_DESCRIPTOR`, never reaching
`idVendor`; the dock's own RTL8153 works). They did not help.

- **Extra kernel args:**
  `-console console=tty0 usbcore.old_scheme_first=1 usbcore.use_both_schemes=1 usbcore.initial_descriptor_timeout=10000 usbcore.autosuspend=-1 pcie_aspm=off`

## `57b306f2…3de9` — PXE boot assets

Used by `heim-pxe-server` (kernel + initramfs for the metal installer over iPXE).
See that repo's README for regeneration.
