# OpenVPN GUI - Vala Version

A GTK+ 3.0 OpenVPN connection manager written in Vala.

## Requirements

- Vala compiler
- GTK+ 3.0 development files
- GLib development files
- Meson build system
- Ninja
- OpenVPN
- pkexec (PolicyKit)

## Installation

### On Ubuntu/Debian:
```bash
sudo apt install valac gtk3-dev libglib2.0-dev meson ninja-build
```

### On Fedora:
```bash
sudo dnf install vala gtk3-devel glib2-devel meson ninja-build
```

## Building

```bash
meson setup builddir
ninja -C builddir
```

## Running

```bash
./builddir/openvpn-gui
```

Or install and run:
```bash
sudo ninja -C builddir install
openvpn-gui
```

## Features

- GUI-based OpenVPN connection manager
- Real-time connection output display
- Status indicator
- Connect/Disconnect buttons
- Root privilege elevation via pkexec
- Auto-scrolling output log

## Configuration

Edit the `config_file` path in the OpenVPNManager class to point to your OpenVPN configuration file.

Current default: `/home/arme/Downloads/profile-7850987265922162575.ovpn`
