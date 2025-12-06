# OpenVPN 3 GUI Manager

A graphical profile manager and automation script for OpenVPN 3 on Linux, featuring a modern GUI interface with Zenity, Multi-Factor Authentication (MFA/OTP) support, and seamless session management.

![Profile Manager](https://img.shields.io/badge/GUI-Zenity-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-Linux-orange)

## Features

*   **🖥️ Profile Manager GUI**: Visual interface to browse, connect, import, and delete VPN profiles.
*   **🔐 Interactive Setup Wizard**: Guides you through importing `.ovpn` files and setting up credentials on first run.
*   **⚡ Automated Login**: Automatically fills username and password from a secure credential file.
*   **📱 MFA/OTP Support**: Prompts for the Authenticator Code via a GUI dialog (Zenity) or terminal fallback.
*   **📦 Dependency Checking**: Automatically detects missing packages and shows distribution-specific install commands (Arch, Debian, Fedora, RHEL, SUSE).
*   **✅ Configuration Validation**: Verifies that the requested OpenVPN configuration profile exists before attempting to connect.
*   **🔍 Session Detection**: Checks if a session is already active for the specified configuration.
*   **📊 Status Dashboard**: If connected, shows session details (config, remote, device, PID, DBus path) in a tabular GUI dialog.
*   **🔌 Easy Disconnect**: Status dialog offers **Disconnect**, **Keep Connected**, and an **Exit** button to close the app.
*   **🎨 Modern UI**: Emoji icons and intuitive button layout for better user experience.

## Prerequisites

Ensure you have the following installed:

*   **OpenVPN 3 Linux Client** (v26 or later recommended)
*   **Expect**: `sudo pacman -S expect` (Arch) or `sudo apt install expect` (Debian/Ubuntu)
*   **Zenity**: `sudo pacman -S zenity` (Arch) or `sudo apt install zenity` (Debian/Ubuntu) *(optional, for GUI dialogs)*

### Quick Dependency Check

Run the script with `--check` to verify all dependencies are installed:

```bash
./openvpn3-auto.expect --check
```

This will show you:
- Which packages are installed
- Which packages are missing
- Distribution-specific installation commands

If any required dependencies are missing, the script will automatically show installation instructions when you try to run it.

## Quick Start (New Users)

The easiest way to get started is to simply run the script. If no configuration exists, it will guide you through the setup:

```bash
chmod +x openvpn3-auto.expect
./openvpn3-auto.expect
```

The setup wizard will:
1. Prompt you to select your `.ovpn` file (via GUI file picker or terminal)
2. Import the configuration into OpenVPN 3
3. Help you set up your credentials securely

You can also force the setup wizard at any time:

```bash
./openvpn3-auto.expect --setup
```

## Manual Setup

If you prefer to set things up manually:

1.  **Import your OpenVPN Profile**:
    Import your `.ovpn` file. The command below assigns it the name `wha-traffic`, which matches the script's default setting.
    ```bash
    openvpn3 config-import --config <your-profile>.ovpn --name wha-traffic --persistent
    ```
    > **Note**: The script defaults to `wha-traffic`. If you use a different name here, you must pass it as an argument when running the script.

2.  **Create Credential File**:
    Create a file to store your credentials (e.g., `~/.config/openvpn3/credentials`).
    *   Line 1: Username
    *   Line 2: Password

    ```bash
    mkdir -p ~/.config/openvpn3
    nano ~/.config/openvpn3/credentials
    chmod 600 ~/.config/openvpn3/credentials  # Secure the file
    ```

3.  **Make Script Executable**:
    ```bash
    chmod +x openvpn3-auto.expect
    ```

## Usage

Run the script from your terminal:

```bash
./openvpn3-auto.expect [OPTIONS] [CONFIG_NAME] [CREDENTIAL_FILE]
```

### Options

*   `--help, -h`: Show help message with usage information.
*   `--check, -c`: Check dependencies and show installation instructions.
*   `--list, -l`: Show the profile manager GUI to choose from available VPN profiles.
*   `--setup, -s`: Run the interactive setup wizard (import .ovpn and set credentials).
*   `--delete, -d`: Delete a VPN profile (shows selection dialog or deletes specified profile).
*   `--version, -v`: Show version information.

### Arguments

*   `CONFIG_NAME`: The name of the imported OpenVPN configuration. If not specified, shows the profile manager GUI.
*   `CREDENTIAL_FILE`: Path to the file containing username and password (Default: `~/.config/openvpn3/credentials`).

### Examples

**Show profile manager (default):**
```bash
./openvpn3-auto.expect
```

**Show profile manager explicitly:**
```bash
./openvpn3-auto.expect --list
```

**Import a new profile:**
```bash
./openvpn3-auto.expect --setup
```

**Delete a profile (interactive):**
```bash
./openvpn3-auto.expect --delete
```

**Delete a specific profile:**
```bash
./openvpn3-auto.expect --delete my-vpn-profile
```

**Connect to a specific config directly:**
```bash
./openvpn3-auto.expect my-vpn-profile
```

**Use specific config and credential file:**
```bash
./openvpn3-auto.expect my-vpn-profile ~/secrets/vpn-creds.txt
```

## How it Works

### Profile Manager GUI

When run without arguments (or with `--list`), the script opens a profile manager window. Connect is via double-click (there is no Connect button); the buttons below handle import/delete/exit:

| Button | Action |
|--------|--------|
| 📡 **Double-click profile** | Connect to the selected VPN profile |
| 🔄 **Refresh** | Reload the profile list and status |
| ➕ **Import New** | Import a new `.ovpn` configuration file |
| 🗑️ **Delete** | Remove the selected profile (with confirmation) |
| ❌ **Exit** | Close the profile manager |

### Connection Flow

1. **Validate Config**: The script checks if the selected profile exists in `openvpn3 configs-list`.
2. **Check Status**: It queries `openvpn3 sessions-list` to see if a session is already active.
3. **Active Session**:
    * If connected, shows a status dialog with connection details (IP, duration, data transfer).
    * Click **🔌 Disconnect** to terminate the session.
    * Click **✅ Keep Connected** to leave the session running.
    * Click **🚪 Exit** to close the script.
4. **New Connection**:
    * Initiates `openvpn3 session-start` for the selected profile.
    * Automatically fills username and password from the credentials file.
    * Shows a 🔐 OTP dialog when the server requests multi-factor authentication.
    * Once authenticated, displays connection logs in the terminal.

### Terminal Fallback

If Zenity is not installed, the script provides a terminal-based menu with the same functionality.

## Troubleshooting & Known Issues

### 1. "error while loading shared libraries: libprotobuf.so.X"
If you encounter errors about missing `libprotobuf` (e.g., `libprotobuf.so.23`), it usually means the `openvpn3` package was built against an older version of the library than what is currently installed on your Arch system.

**Fix**: Rebuild the package to link against the current libraries.
```bash
paru -S openvpn3 --rebuild
```

### 2. D-Bus Timeouts or "Session manager not available"
If `openvpn3 sessions-list` hangs or returns D-Bus errors, the background services might be crashing (often due to the library issue above).

**Fix**: Check logs via `journalctl -xe | grep openvpn3`. If they are segfaulting, rebuild the package as above.

### 3. Connection Timeouts
If the client stays at `Client connecting...` indefinitely:
*   **Firewall**: Ensure your firewall (UFW/IPTables) allows outgoing UDP traffic on port 1194 (or the port specified in your config).
*   **Network**: Verify you can reach the VPN endpoint.
    ```bash
    nc -u -v -z vpn-traffic.wha-digital.com 1194
    ```

### 4. "Auth Failed" loops
Ensure your OTP code is entered correctly. The script waits for the specific prompt "Enter Authenticator Code:". If the server sends a different prompt string, the `expect` script might need adjustment.

### 5. "Configuration profile ... not found"
If you see this error, it means the `CONFIG_NAME` you are trying to use has not been imported into OpenVPN 3.
**Fix**: Run the import command shown in the error message or the [Setup](#setup) section.
```bash
openvpn3 config-import --config <your-profile>.ovpn --name <CONFIG_NAME> --persistent
```

### 6. Delete confirmation seems ignored
If you click **Yes, Delete** and nothing happens, Zenity may be printing a warning to stderr (e.g., deprecated `--icon-name`) while returning exit code 0. The script now treats that as success, but if you still hit it:
* Update Zenity to the latest version.
* Run the terminal fallback: `./openvpn3-auto.expect --delete <profile>`.

## Supported Distributions

The script automatically detects your Linux distribution and provides appropriate installation commands:

| Distribution | Package Manager |
|--------------|----------------|
| 🏔️ Arch Linux | `pacman` |
| 🍥 Debian/Ubuntu | `apt` |
| 🎩 Fedora | `dnf` |
| 🎩 RHEL/CentOS | `yum` |
| 🦎 openSUSE | `zypper` |

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is open source and available under the [MIT License](LICENSE).

