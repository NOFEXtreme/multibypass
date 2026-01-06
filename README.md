# Multibypass

**Multibypass** is a project that easily integrates [zapret](https://github.com/bol-van/zapret) for DPI bypass and [x3mRouting](https://github.com/NOFEXtreme/x3mRouting/blob/master/x3mRouting.sh) for domain-based VPN routing on [ASUSWRT-Merlin](https://github.com/gnuton/asuswrt-merlin.ng).

Dependencies:

- [ASUS-Merlin](https://www.asuswrt-merlin.net/) 3004.388.9 or newer for x3mRouting
- [Entware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware)

Tested on models:

- **RT-AX82U**
- **RT-AX58U V2**
- **TUF-AX3000 V2**

---

### Quick Start

1. Login to your router via ssh.
2. Download the latest [releases](https://github.com/NOFEXtreme/multibypass/releases). <sub>( *auto-extract to: `/jffs/scripts/multibypass`*)</sub>
   ```bash
   curl -fsSL https://github.com/NOFEXtreme/multibypass/releases/latest/download/multibypass.tar.gz | tar -xzv -C /jffs/scripts/
   ```
3. Run the installation:
    ```bash
    sh /jffs/scripts/multibypass/bypass.sh install
    ```
4. For additional commands and options, view the help menu:
    ```bash
    sh /jffs/scripts/multibypass/bypass.sh help
    ```

**Notes:**

- For x3mRouting, if domains files are missing, you will be prompted to create them when enabling WireGuard or OpenVPN routing.
- For better DPI bypass, edit the zapret-config.sh file. Instructions can be found here: [Zapret README](https://github.com/bol-van/zapret/blob/master/docs/readme.en.md).

---

### Update

1. Login to your router via ssh.
2. Run the update:
   ```bash
   sh /jffs/scripts/multibypass/bypass.sh update
   ```
   *will automatically download and install the latest version.*

   > Files in `zapret-custom.d` are always overwritten during update. If you’ve modified them, back up or rename them beforehand.  

   > `zapret-config.sh` is not overwritten; it’s recommended to compare it with the release and merge any changes if needed.

---

### Uninstall

1. Login to your router via ssh.
2. Run the uninstallation process:
   ```bash
   sh /jffs/scripts/multibypass/bypass.sh uninstall
   ```
   *will ask for confirmation and if you want to save the config files.*

---

### Working with the source code

##### Clone the repository with submodules:

```bash
git clone --recurse-submodules https://github.com/NOFEXtreme/multibypass.git
```

##### To update submodules:

```bash
git submodule update --remote --recursive
```

---

<div align="center">

[![Release Stats](https://img.shields.io/badge/Release%20stats-34495E?style=for-the-badge&color=2d4053&labelColor=2d4053)](https://somsubhra.github.io/github-release-stats/?username=NOFEXtreme&repository=multibypass)
[![Latest](https://img.shields.io/github/release/NOFEXtreme/multibypass.svg?label=Latest&style=for-the-badge&color=435f7d&labelColor=2d4053)](https://github.com/NOFEXtreme/multibypass/releases/latest)
[![Date](https://img.shields.io/github/release-date/NOFEXtreme/multibypass.svg?label=Date&style=for-the-badge&color=435f7d&labelColor=2d4053)](https://github.com/NOFEXtreme/multibypass/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/NOFEXtreme/multibypass/total.svg?label=Downloads&style=for-the-badge&color=435f7d&labelColor=2d4053)](https://github.com/NOFEXtreme/multibypass/releases/latest)

</div>
