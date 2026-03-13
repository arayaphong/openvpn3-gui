using Gtk;
using GLib;

class OpenVPNManager : Object {
    private Subprocess? process = null;
    public string config_file { get; set; default = ""; }
    public bool connected { get; set; default = false; }
    
    public signal void output_received(string text);
    public signal void error_received(string text);
    
    public OpenVPNManager() {
        Object();
    }
    
    public new void connect() {
        if (this.config_file == "") {
            error_received("No configuration file selected");
            return;
        }
        
        if (this.process != null) {
            error_received("Already connected or connecting");
            return;
        }
        
        try {
            string[] cmd = { "pkexec", "openvpn", "--config", this.config_file };
            this.process = new Subprocess.newv(
                (owned) cmd,
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
            );
            
            read_output_async.begin();
            read_error_async.begin();
            
            this.process.wait_async.begin(null, (obj, res) => {
                try {
                    this.process.wait_async.end(res);
                    output_received("\n--- Process exited ---\n");
                } catch (Error e) {
                    error_received("Wait error: " + e.message);
                }
                this.process = null;
                this.connected = false;
            });
        } catch (Error e) {
            error_received("Process error: " + e.message);
            this.process = null;
            this.connected = false;
        }
    }
    
    private async void read_output_async() {
        if (this.process == null) return;
        
        var stdout = this.process.get_stdout_pipe();
        var dis = new DataInputStream(stdout);
        
        try {
            string? line = yield dis.read_line_async(Priority.DEFAULT);
            while (line != null) {
                output_received(line + "\n");
                
                if (line.contains("Initialization Sequence Completed")) {
                    this.connected = true;
                    output_received("✓ VPN Connected Successfully!\n");
                }
                if (line.contains("Server poll timeout")) {
                    error_received("⚠ Connection timeout - server not responding");
                }
                if (line.contains("AUTH_FAILED")) {
                    error_received("Authentication failed: " + line);
                }
                
                line = yield dis.read_line_async(Priority.DEFAULT);
            }
        } catch (Error e) {
            error_received("Read error: " + e.message);
        }
    }
    
    private async void read_error_async() {
        if (this.process == null) return;
        
        var stderr = this.process.get_stderr_pipe();
        var dis = new DataInputStream(stderr);
        
        try {
            string? line = yield dis.read_line_async(Priority.DEFAULT);
            while (line != null) {
                output_received("[ERROR] " + line + "\n");
                line = yield dis.read_line_async(Priority.DEFAULT);
            }
        } catch (GLib.IOError e) {
            error_received("Stderr read error: " + e.message);
        }
    }
    
    
    public new void disconnect() {
        output_received("Disconnecting VPN...\n");
        
        // If we have a process we started, terminate it
        if (this.process != null) {
            this.process.send_signal(Posix.Signal.TERM);
            this.process = null;
        } else {
            // If no process in our manager, try to kill openvpn via system command
            try {
                string stdout_str;
                string stderr_str;
                int exit_status;
                Process.spawn_command_line_sync(
                    "pkexec killall -9 openvpn",
                    out stdout_str,
                    out stderr_str,
                    out exit_status
                );
                if (exit_status != 0 && exit_status != 1) {
                    output_received("Warning: killall exit code " + exit_status.to_string() + "\n");
                }
                if (stderr_str != "") {
                    output_received("Stderr: " + stderr_str + "\n");
                }
            } catch (Error e) {
                output_received("Error killing openvpn: " + e.message + "\n");
            }
        }
        
        this.connected = false;
        output_received("✓ VPN Disconnected\n");
    }
}

class OpenVPNGui : ApplicationWindow {
    private OpenVPNManager vpn_manager;
    private Button connect_btn;
    private Button disconnect_btn;
    private Label status_label;
    private Label config_label;
    private TextView text_view;
    private TextView history_view;

    public OpenVPNGui(Gtk.Application app) {
        Object(application: app);

        this.vpn_manager = new OpenVPNManager();

        this.set_title("OpenVPN GUI");
        this.set_default_size(600, 400);
        this.set_border_width(10);

        build_ui();

        // Auto-load .ovpn file from executable directory
        auto_load_config_file();
        
        // Check initial VPN connection status and update buttons
        check_and_update_connection_status();

        this.delete_event.connect(() => {
            if (this.vpn_manager.connected) {
                this.vpn_manager.disconnect();
            }
            return false;
        });
    }

    private void build_ui() {
        // Main horizontal container for left and right panels
        var main_hbox = new Box(Orientation.HORIZONTAL, 10);

        // Left panel (main controls)
        var vbox = new Box(Orientation.VERTICAL, 10);
        vbox.set_margin_top(10);
        vbox.set_margin_bottom(10);
        vbox.set_margin_start(10);
        vbox.set_margin_end(10);

        // Header
        var header_label = new Label(null);
        header_label.set_markup("<b>OpenVPN Connection Manager</b>");
        vbox.pack_start(header_label, false, false, 0);

        // Config info with browse button
        var config_box = new Box(Orientation.HORIZONTAL, 10);

        this.config_label = new Label(null);
        if (this.vpn_manager.config_file == "") {
            this.config_label.set_markup("<small>Config: <i>No file selected</i></small>");
        } else {
            this.config_label.set_markup("<small>Config: %s</small>".printf(this.vpn_manager.config_file));
        }
        this.config_label.set_xalign(0);
        this.config_label.set_ellipsize(Pango.EllipsizeMode.MIDDLE);
        config_box.pack_start(this.config_label, true, true, 0);

        var browse_btn = new Button.with_label("Browse...");
        browse_btn.clicked.connect(on_browse);
        config_box.pack_start(browse_btn, false, false, 0);

        vbox.pack_start(config_box, false, false, 0);

        // Buttons
        var button_box = new Box(Orientation.HORIZONTAL, 10);

        this.connect_btn = new Button.with_label("Connect");
        this.connect_btn.set_sensitive(false);
        this.connect_btn.clicked.connect(on_connect);
        button_box.pack_start(this.connect_btn, true, true, 0);

        this.disconnect_btn = new Button.with_label("Disconnect");
        this.disconnect_btn.set_sensitive(false);
        this.disconnect_btn.clicked.connect(on_disconnect);
        button_box.pack_start(this.disconnect_btn, true, true, 0);

        vbox.pack_start(button_box, false, false, 0);

        // Status indicator
        this.status_label = new Label("Status: Disconnected");
        this.status_label.set_xalign(0);
        vbox.pack_start(this.status_label, false, false, 0);

        // Separator
        vbox.pack_start(new Separator(Orientation.HORIZONTAL), false, false, 5);

        // Output area
        var scrolled = new ScrolledWindow(null, null);
        scrolled.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);

        this.text_view = new TextView();
        this.text_view.set_editable(false);
        this.text_view.set_wrap_mode(WrapMode.WORD_CHAR);
        this.text_view.set_monospace(true);

        var buffer = this.text_view.get_buffer();
        buffer.set_text("Ready to connect...\n", -1);

        scrolled.add(this.text_view);
        vbox.pack_start(scrolled, true, true, 0);

        main_hbox.pack_start(vbox, true, true, 0);

        // Right panel (connection history)
        var right_vbox = new Box(Orientation.VERTICAL, 5);
        right_vbox.set_margin_top(10);
        right_vbox.set_margin_bottom(10);
        right_vbox.set_margin_end(10);

        var history_header = new Label(null);
        history_header.set_markup("<b>Connection History</b>");
        history_header.set_xalign(0);
        right_vbox.pack_start(history_header, false, false, 0);

        // Refresh sessions button
        var refresh_sessions_btn = new Button.with_label("Refresh Sessions");
        refresh_sessions_btn.clicked.connect(on_refresh_sessions);
        right_vbox.pack_start(refresh_sessions_btn, false, false, 5);

        var history_scrolled = new ScrolledWindow(null, null);
        history_scrolled.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        history_scrolled.set_size_request(250, -1);

        this.history_view = new TextView();
        this.history_view.set_editable(false);
        this.history_view.set_wrap_mode(WrapMode.WORD_CHAR);
        this.history_view.set_monospace(true);

        var history_buffer = this.history_view.get_buffer();
        history_buffer.set_text("No connections yet.\n", -1);

        history_scrolled.add(this.history_view);
        right_vbox.pack_start(history_scrolled, true, true, 0);

        main_hbox.pack_start(right_vbox, false, false, 0);

        this.add(main_hbox);
        this.show_all();

        // Connect signals
        this.vpn_manager.output_received.connect(on_output);
        this.vpn_manager.error_received.connect(on_error);
    }

    private string get_config_file_path() {
        var home = GLib.Environment.get_home_dir();
        var vpn_dir = GLib.Path.build_filename(home, ".vpn");
        return GLib.Path.build_filename(vpn_dir, "config.ini");
    }

    private string? load_last_config_file() {
        try {
            var config_path = get_config_file_path();
            var file = File.new_for_path(config_path);

            if (!file.query_exists()) {
                return null;
            }

            var key_file = new KeyFile();
            key_file.load_from_file(config_path, KeyFileFlags.NONE);

            if (key_file.has_group("config") && key_file.has_key("config", "last_file")) {
                string last_file = key_file.get_value("config", "last_file");
                // Verify the file still exists
                var config_file = File.new_for_path(last_file);
                if (config_file.query_exists()) {
                    return last_file;
                }
            }
        } catch (Error e) {
            append_output("Error reading config file: %s\n".printf(e.message));
        }
        return null;
    }

    private void save_config_file(string config_file) {
        try {
            var home = GLib.Environment.get_home_dir();
            var vpn_dir = GLib.Path.build_filename(home, ".vpn");
            var dir = File.new_for_path(vpn_dir);

            // Create ~/.vpn directory if it doesn't exist
            if (!dir.query_exists()) {
                dir.make_directory_with_parents();
            }

            var config_path = get_config_file_path();
            var key_file = new KeyFile();

            // Load existing config if it exists
            var file = File.new_for_path(config_path);
            if (file.query_exists()) {
                key_file.load_from_file(config_path, KeyFileFlags.NONE);
            }

            key_file.set_value("config", "last_file", config_file);
            key_file.save_to_file(config_path);
        } catch (Error e) {
            append_output("Error saving config file: %s\n".printf(e.message));
        }
    }

    private void auto_load_config_file() {
        var last_config = load_last_config_file();
        if (last_config != null) {
            this.vpn_manager.config_file = last_config;
            this.config_label.set_markup("<small>Config: %s</small>".printf(last_config));
            append_output("Auto-loaded configuration file: %s\n".printf(last_config));
        }
    }

    private void check_and_update_connection_status() {
        try {
            string stdout_str;
            string stderr_str;
            int exit_status;

            // Check if tun devices exist using sh -c for proper shell parsing
            Process.spawn_command_line_sync(
                "sh -c \"ip link show | grep tun\"",
                out stdout_str,
                out stderr_str,
                out exit_status
            );

            if (exit_status == 0 && stdout_str != "") {
                // VPN is connected
                this.status_label.set_label("Status: Connected (detected on startup)");
                this.disconnect_btn.set_sensitive(true);
                this.connect_btn.set_sensitive(false);
                append_output("Detected active VPN connection on startup.\n");
            } else {
                // VPN is not connected - enable connect button if config is loaded
                if (this.vpn_manager.config_file != "") {
                    this.connect_btn.set_sensitive(true);
                }
                this.disconnect_btn.set_sensitive(false);
            }
        } catch (Error e) {
            append_output("Error checking connection status: " + e.message + "\n");
        }
    }

    private void append_output(string text) {
        var buffer = this.text_view.get_buffer();
        TextIter end_iter;
        buffer.get_end_iter(out end_iter);
        buffer.insert(ref end_iter, text, -1);
        scroll_to_bottom(this.text_view);
    }
    
    private void scroll_to_bottom(TextView view) {
        var mark = view.get_buffer().get_insert();
        view.scroll_to_mark(mark, 0.0, true, 0.0, 1.0);
    }

    private void append_history(string text) {
        var buffer = this.history_view.get_buffer();

        // Clear "No connections yet" message if it's the first entry
        TextIter start, end;
        buffer.get_start_iter(out start);
        buffer.get_end_iter(out end);
        string current_text = buffer.get_text(start, end, false);
        if (current_text.strip() == "No connections yet.") {
            buffer.set_text("", -1);
        }

        // Get current timestamp
        var now = new DateTime.now_local();
        string timestamp = now.format("%Y-%m-%d %H:%M:%S");

        TextIter end_iter;
        buffer.get_end_iter(out end_iter);
        buffer.insert(ref end_iter, "[%s] %s\n".printf(timestamp, text), -1);
        scroll_to_bottom(this.history_view);
    }

    private void on_output(string text) {
        append_output(text);

        if (this.vpn_manager.connected) {
            this.status_label.set_label("Status: Connected");
            this.disconnect_btn.set_sensitive(true);
            this.connect_btn.set_sensitive(false);
            if (text.contains("VPN Connected Successfully")) {
                append_history("Connected");
            }
        } else if (text.contains("Process exited")) {
            this.status_label.set_label("Status: Disconnected");
            this.disconnect_btn.set_sensitive(false);
            if (this.vpn_manager.config_file != "") {
                this.connect_btn.set_sensitive(true);
            }
        }
    }

    private void on_error(string error) {
        append_output("ERROR: " + error + "\n");
        this.status_label.set_label("Status: Connection Failed");
        this.connect_btn.set_sensitive(true);
        this.disconnect_btn.set_sensitive(false);
        append_history("Connection failed: " + error);
    }

    private void on_connect() {
        this.connect_btn.set_sensitive(false);
        this.status_label.set_label("Status: Connecting...");
        append_output("\n=== Connecting to VPN ===\n");
        append_history("Attempting connection...");

        this.vpn_manager.connect();
    }

    private void on_disconnect() {
        this.disconnect_btn.set_sensitive(false);
        this.vpn_manager.disconnect();
        
        // Give the system a moment to process the kill command
        Timeout.add(500, () => {
            verify_disconnection();
            return false;
        });
    }
    
    private void verify_disconnection() {
        try {
            string stdout_str;
            string stderr_str;
            int exit_status;
            
            // Check if tun devices still exist
            Process.spawn_command_line_sync(
                "sh -c \"ip link show | grep tun\"",
                out stdout_str,
                out stderr_str,
                out exit_status
            );
            
            // If no tun devices found (exit_status != 0), VPN is really disconnected
            if (exit_status != 0 || stdout_str == "") {
                this.status_label.set_label("Status: Disconnected");
                if (this.vpn_manager.config_file != "") {
                    this.connect_btn.set_sensitive(true);
                }
                append_history("Disconnected");
            } else {
                // Still connected, try killing again
                append_output("VPN still running, attempting force kill...\n");
                this.vpn_manager.disconnect();
            }
        } catch (Error e) {
            append_output("Verification error: " + e.message + "\n");
        }
    }

    private void on_browse() {
        var file_chooser = new FileChooserDialog(
            "Select OpenVPN Configuration File",
            this,
            FileChooserAction.OPEN,
            "_Cancel", ResponseType.CANCEL,
            "_Open", ResponseType.ACCEPT
        );

        // Add file filter for .ovpn and .conf files
        var filter = new FileFilter();
        filter.set_filter_name("OpenVPN Config Files");
        filter.add_pattern("*.ovpn");
        filter.add_pattern("*.conf");
        file_chooser.add_filter(filter);

        var filter_all = new FileFilter();
        filter_all.set_filter_name("All Files");
        filter_all.add_pattern("*");
        file_chooser.add_filter(filter_all);

        if (file_chooser.run() == ResponseType.ACCEPT) {
            var selected_file = file_chooser.get_filename();
            this.vpn_manager.config_file = selected_file;
            this.config_label.set_markup("<small>Config: %s</small>".printf(selected_file));
            this.connect_btn.set_sensitive(true);
            append_output("Configuration file selected: %s\n".printf(selected_file));

            // Save the selected file to config
            save_config_file(selected_file);
        }

        file_chooser.destroy();
    }

    private void on_refresh_sessions() {
        try {
            string stdout_str;
            string stderr_str;
            int exit_status;

            // Check VPN connection status using ip link
            Process.spawn_command_line_sync(
                "ip link show",
                out stdout_str,
                out stderr_str,
                out exit_status
            );

            // Clear history and show status
            var buffer = this.history_view.get_buffer();
            buffer.set_text("", -1);

            if (exit_status == 0) {
                // Parse output to find active tun devices
                var lines = stdout_str.split("\n");
                append_to_history_direct("=== Network Interfaces ===");

                foreach (string line in lines) {
                    if (line.contains("tun") || line.contains("UP")) {
                        append_to_history_direct(line);
                    }
                }

                // Check VPN routes
                Process.spawn_command_line_sync(
                    "sh -c \"ip route | grep tun\"",
                    out stdout_str,
                    out stderr_str,
                    out exit_status
                );

                append_to_history_direct("\n=== VPN Routes ===");
                if (exit_status == 0 && stdout_str != "") {
                    var route_lines = stdout_str.split("\n");
                    foreach (string line in route_lines) {
                        if (line.strip() != "") {
                            append_to_history_direct(line);
                        }
                    }
                } else {
                    append_to_history_direct("No active VPN routes found.");
                }
            }

            append_output("Connection status refreshed.\n");
        } catch (Error e) {
            append_output("Error checking connection status: " + e.message + "\n");
            append_to_history_direct("Error: " + e.message);
        }
    }

    private void append_to_history_direct(string text) {
        var buffer = this.history_view.get_buffer();
        TextIter end_iter;
        buffer.get_end_iter(out end_iter);
        buffer.insert(ref end_iter, text + "\n", -1);
        scroll_to_bottom(this.history_view);
    }
}

class OpenVPNApplication : Gtk.Application {
    protected override void activate() {
        var window = new OpenVPNGui(this);
        window.show();
    }
}

int main(string[] args) {
    var app = new OpenVPNApplication();
    return app.run(args);
}
