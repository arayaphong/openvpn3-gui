# OpenVPN 3 Automation Helper

This project contains an automation script (`openvpn3-auto.expect`) designed to streamline the connection process for OpenVPN 3 on Linux, specifically handling Multi-Factor Authentication (MFA/OTP) and session management.

## Features

*   **Automated Login**: Automatically fills username and password from a secure credential file.
*   **MFA Support**: Prompts for the Authenticator Code (OTP) via a GUI dialog (Zenity) or terminal fallback.
*   **Configuration Validation**: Verifies that the requested OpenVPN configuration profile exists before attempting to connect.
*   **Session Detection**: Checks if a session is already active for the specified configuration.
*   **Status Dashboard**: If connected, displays session details (IP, duration, data transfer) in a GUI dialog.
*   **Easy Disconnect**: Provides a "Disconnect" button in the status dialog to terminate the active session.

## Prerequisites

Ensure you have the following installed:

*   **OpenVPN 3 Linux Client** (v26 or later recommended)
*   **Expect**: `sudo pacman -S expect` (Arch) or `sudo apt install expect` (Debian/Ubuntu)
*   **Zenity**: `sudo pacman -S zenity` (Arch) or `sudo apt install zenity` (Debian/Ubuntu)

## Setup

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
./openvpn3-auto.expect [CONFIG_NAME] [CREDENTIAL_FILE]
```

### Arguments

*   `CONFIG_NAME`: The name of the imported OpenVPN configuration (Default: `wha-traffic`).
*   `CREDENTIAL_FILE`: Path to the file containing username and password (Default: `~/.config/openvpn3/credentials`).

### Examples

**Use defaults:**
```bash
./openvpn3-auto.expect
```

**Use a specific config:**
```bash
./openvpn3-auto.expect my-vpn-profile
```

**Use specific config and credential file:**
```bash
./openvpn3-auto.expect my-vpn-profile ~/secrets/vpn-creds.txt
```

## How it Works

1.  **Validate Config**: The script checks if the specified configuration profile (default `wha-traffic`) exists in `openvpn3 configs-list`.
2.  **Check Status**: It runs `openvpn3 sessions-list` to see if a session is already active for that config.
3.  **Active Session**:
    *   If connected, it opens a Zenity dialog showing connection details.
    *   Clicking **Disconnect** will terminate the session.
    *   Clicking **Keep Connected** (or closing the dialog) leaves the session running.
4.  **New Connection**:
    *   If not connected, it initiates `openvpn3 session-start`.
    *   It waits for the `Auth User name:` and `Auth Password:` prompts and fills them in.
    *   It pops up a Zenity input box for your MFA/OTP code.
    *   Once authenticated, it hands control back to the terminal so you can see the connection logs.

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

