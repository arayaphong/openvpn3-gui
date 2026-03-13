using Gtk;
using GLib;

class OpenVPNManager : Object {
    private Subprocess? process = null;
    private string openvpn3_path = "openvpn3";
    public string config_file { get; set; default = ""; }
    public bool has_openvpn3_cli { get; private set; default = false; }
    public bool connected { get; set; default = false; }
    public string session_path { get; set; default = ""; }
    
    public signal void output_received(string text);
    public signal void error_received(string text);
    
    public OpenVPNManager() {
        Object();
        this.has_openvpn3_cli = detect_openvpn3_cli();
    }

    private bool detect_openvpn3_cli() {
        string[] candidates = { "/usr/bin/openvpn3", "/usr/local/bin/openvpn3", "/bin/openvpn3" };
        foreach (string candidate in candidates) {
            if (File.new_for_path(candidate).query_exists()) {
                this.openvpn3_path = candidate;
                return true;
            }
        }

        try {
            string out_str;
            string err_str;
            int exit_status;
            Process.spawn_command_line_sync("command -v openvpn3", out out_str, out err_str, out exit_status);
            if (exit_status == 0 && out_str.strip() != "") {
                this.openvpn3_path = out_str.strip();
                return true;
            }
            return false;
        } catch (Error e) {
            return false;
        }
    }
    
    public new void connect() {
        if (this.config_file == "") {
            error_received("No configuration file selected");
            return;
        }

        if (!this.has_openvpn3_cli) {
            error_received("openvpn3 CLI is not installed. Please install openvpn3 and retry.");
            return;
        }
        
        if (this.process != null) {
            error_received("Already connected or connecting");
            return;
        }
        
        try {
            this.session_path = "";
            string[] cmd = { this.openvpn3_path, "session-start", "--config", this.config_file };
            this.process = new Subprocess.newv(
                (owned) cmd,
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
            );
            
            read_output_async.begin();
            read_error_async.begin();
            
            this.process.wait_async.begin(null, (obj, res) => {
                try {
                    this.process.wait_async.end(res);
                    int exit_code = this.process.get_exit_status();
                    if (this.connected) {
                        output_received("\n--- OpenVPN 3 command completed; VPN session is managed by background service ---\n");
                    } else if (exit_code != 0) {
                        error_received("OpenVPN 3 session-start failed with exit code " + exit_code.to_string());
                    } else {
                        error_received("OpenVPN 3 exited without confirming tunnel activation.");
                    }
                } catch (Error e) {
                    error_received("Wait error: " + e.message);
                }
                this.process = null;
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

                if (line.contains("Session path:")) {
                    var parts = line.split("Session path:");
                    if (parts.length > 1) {
                        this.session_path = parts[1].strip();
                        // OpenVPN3 created a session; mark as connected from UI perspective.
                        this.connected = true;
                    }
                }
                
                if (line.contains("Initialization Sequence Completed")) {
                    this.connected = true;
                    output_received("✓ VPN Connected Successfully!\n");
                }
                if (line.contains("Connected to ")) {
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
        // Mark disconnected before emitting output so UI handlers do not re-enable buttons.
        this.connected = false;
        output_received("Disconnecting VPN...\n");

        try {
            string[] cmd;
            if (this.session_path != "") {
                cmd = { this.openvpn3_path, "session-manage", "--disconnect", "--path", this.session_path };
            } else {
                cmd = { this.openvpn3_path, "session-manage", "--disconnect", "--config", this.config_file };
            }

            var disconnect_proc = new Subprocess.newv(
                (owned) cmd,
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
            );

            disconnect_proc.wait_async.begin(null, (obj, res) => {
                try {
                    disconnect_proc.wait_async.end(res);
                    if (disconnect_proc.get_exit_status() == 0) {
                        this.session_path = "";
                        output_received("OpenVPN 3 disconnect command sent.\n");
                    } else {
                        output_received("OpenVPN 3 disconnect returned code " + disconnect_proc.get_exit_status().to_string() + "\n");
                    }
                } catch (Error e) {
                    output_received("OpenVPN 3 disconnect error: " + e.message + "\n");
                }
            });
        } catch (Error e) {
            output_received("OpenVPN 3 disconnect start error: " + e.message + "\n");
        }
        
        output_received("Disconnect signal sent.\n");
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
    private Image status_icon;
    private Dialog logs_dialog;
    private int disconnect_verify_attempts = 0;

    public OpenVPNGui(Gtk.Application app) {
        Object(application: app);

        this.vpn_manager = new OpenVPNManager();

        this.set_title("OpenVPN GUI");
        this.set_default_size(600, 320);
        this.set_resizable(false);
        this.set_border_width(10);

        build_ui();

        // Auto-load .ovpn file from executable directory
        auto_load_config_file();
        
        // Check initial VPN connection status and update buttons
        check_and_update_connection_status();

    }

    private void build_ui() {
        var root = new Box(Orientation.VERTICAL, 12);
        root.set_margin_top(14);
        root.set_margin_bottom(14);
        root.set_margin_start(14);
        root.set_margin_end(14);

        var top_card = new Frame(null);
        top_card.get_style_context().add_class("card");

        var top_box = new Box(Orientation.VERTICAL, 10);
        top_box.set_margin_top(14);
        top_box.set_margin_bottom(14);
        top_box.set_margin_start(14);
        top_box.set_margin_end(14);

        var title_row = new Box(Orientation.HORIZONTAL, 8);
        var title_label = new Label(null);
        title_label.set_markup("<span weight='bold' size='x-large'>OpenVPN Command Center</span>");
        title_label.set_xalign(0);

        var status_box = new Box(Orientation.HORIZONTAL, 6);
        this.status_icon = new Image.from_icon_name("network-offline-symbolic", IconSize.BUTTON);
        this.status_label = new Label(null);
        this.status_label.set_xalign(1);
        update_status("Disconnected", "network-offline-symbolic", "#6b7280");
        status_box.pack_start(this.status_icon, false, false, 0);
        status_box.pack_start(this.status_label, false, false, 0);

        title_row.pack_start(title_label, true, true, 0);
        title_row.pack_end(status_box, false, false, 0);
        top_box.pack_start(title_row, false, false, 0);

        var subtitle = new Label("Connect securely in one click, then open logs only when you need details.");
        subtitle.set_xalign(0);
        top_box.pack_start(subtitle, false, false, 0);

        var config_row = new Box(Orientation.HORIZONTAL, 8);

        var config_icon = new Image.from_icon_name("text-x-generic-symbolic", IconSize.BUTTON);
        config_row.pack_start(config_icon, false, false, 0);

        var config_title = new Label("Config file");
        config_title.set_xalign(0);
        config_row.pack_start(config_title, false, false, 0);

        this.config_label = new Label(null);
        this.config_label.set_xalign(0);
        this.config_label.set_ellipsize(Pango.EllipsizeMode.MIDDLE);
        update_config_label();
        config_row.pack_start(this.config_label, true, true, 0);

        var browse_btn = new Button.with_label("Select File");
        browse_btn.clicked.connect(on_browse);
        config_row.pack_end(browse_btn, false, false, 0);
        top_box.pack_start(config_row, false, false, 0);

        var button_row = new Box(Orientation.HORIZONTAL, 10);

        this.connect_btn = new Button.with_label("Connect");
        this.connect_btn.set_image(new Image.from_icon_name("media-playback-start-symbolic", IconSize.BUTTON));
        this.connect_btn.set_always_show_image(true);
        this.connect_btn.get_style_context().add_class("suggested-action");
        this.connect_btn.set_sensitive(false);
        this.connect_btn.clicked.connect(on_connect);
        button_row.pack_start(this.connect_btn, true, true, 0);

        this.disconnect_btn = new Button.with_label("Disconnect");
        this.disconnect_btn.set_image(new Image.from_icon_name("process-stop-symbolic", IconSize.BUTTON));
        this.disconnect_btn.set_always_show_image(true);
        this.disconnect_btn.get_style_context().add_class("destructive-action");
        this.disconnect_btn.set_sensitive(false);
        this.disconnect_btn.clicked.connect(on_disconnect);
        button_row.pack_start(this.disconnect_btn, true, true, 0);

        top_box.pack_start(button_row, false, false, 0);

        var tools_row = new Box(Orientation.HORIZONTAL, 10);
        tools_row.set_margin_top(2);
        var view_logs_btn = new Button.with_label("View Logs");
        view_logs_btn.set_image(new Image.from_icon_name("text-x-log-symbolic", IconSize.BUTTON));
        view_logs_btn.set_always_show_image(true);
        view_logs_btn.clicked.connect(on_view_logs);
        tools_row.pack_start(view_logs_btn, false, false, 0);
        top_box.pack_start(tools_row, false, false, 0);

        top_card.add(top_box);
        root.pack_start(top_card, false, false, 0);

        var info_card = new Frame(null);
        var info_box = new Box(Orientation.HORIZONTAL, 8);
        info_box.set_margin_top(12);
        info_box.set_margin_bottom(12);
        info_box.set_margin_start(12);
        info_box.set_margin_end(12);

        var info_icon = new Image.from_icon_name("dialog-information-symbolic", IconSize.BUTTON);
        var info_label = new Label("Logs are hidden to keep this screen clean. Use View Logs when you need details.");
        info_label.set_xalign(0);
        info_label.set_line_wrap(true);

        info_box.pack_start(info_icon, false, false, 0);
        info_box.pack_start(info_label, true, true, 0);
        info_card.add(info_box);
        root.pack_start(info_card, false, false, 0);

        create_logs_dialog();

        this.add(root);
        this.show_all();

        // Connect signals
        this.vpn_manager.output_received.connect(on_output);
        this.vpn_manager.error_received.connect(on_error);
    }

    private void create_logs_dialog() {
        this.logs_dialog = new Dialog.with_buttons(
            "OpenVPN Logs",
            this,
            DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT,
            "_Close",
            ResponseType.CLOSE
        );
        this.logs_dialog.set_default_size(860, 520);

        var content = this.logs_dialog.get_content_area();
        content.set_margin_top(8);
        content.set_margin_bottom(8);
        content.set_margin_start(8);
        content.set_margin_end(8);
        content.set_spacing(8);

        var logs_toolbar = new Box(Orientation.HORIZONTAL, 8);
        logs_toolbar.set_margin_bottom(2);
        var refresh_sessions_btn = new Button.with_label("Fetch Network Status");
        refresh_sessions_btn.set_image(new Image.from_icon_name("view-refresh-symbolic", IconSize.BUTTON));
        refresh_sessions_btn.set_always_show_image(true);
        refresh_sessions_btn.clicked.connect(on_refresh_sessions);
        logs_toolbar.pack_start(refresh_sessions_btn, false, false, 0);
        content.pack_start(logs_toolbar, false, false, 0);

        var notebook = new Notebook();
        notebook.set_margin_top(2);

        var live_scrolled = new ScrolledWindow(null, null);
        live_scrolled.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        this.text_view = new TextView();
        this.text_view.set_editable(false);
        this.text_view.set_wrap_mode(WrapMode.NONE);
        this.text_view.set_monospace(true);
        this.text_view.set_left_margin(12);
        this.text_view.set_right_margin(12);
        this.text_view.get_buffer().set_text("Ready to connect...\n", -1);
        live_scrolled.add(this.text_view);

        var live_overlay = new Overlay();
        live_overlay.add_events((int) (Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK));
        live_overlay.add(live_scrolled);
        var live_copy_revealer = create_floating_copy_button(this.text_view, "Copy live output");
        live_overlay.add_overlay(live_copy_revealer);
        live_overlay.enter_notify_event.connect((event) => {
            live_copy_revealer.set_reveal_child(true);
            return false;
        });
        live_overlay.leave_notify_event.connect((event) => {
            live_copy_revealer.set_reveal_child(false);
            return false;
        });
        notebook.append_page(live_overlay, new Label("Live Output"));

        var history_scrolled = new ScrolledWindow(null, null);
        history_scrolled.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        this.history_view = new TextView();
        this.history_view.set_editable(false);
        this.history_view.set_wrap_mode(WrapMode.NONE);
        this.history_view.set_monospace(true);
        this.history_view.set_left_margin(12);
        this.history_view.set_right_margin(12);
        this.history_view.get_buffer().set_text("No connections yet.\n", -1);
        history_scrolled.add(this.history_view);

        var history_overlay = new Overlay();
        history_overlay.add_events((int) (Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK));
        history_overlay.add(history_scrolled);
        var history_copy_revealer = create_floating_copy_button(this.history_view, "Copy history");
        history_overlay.add_overlay(history_copy_revealer);
        history_overlay.enter_notify_event.connect((event) => {
            history_copy_revealer.set_reveal_child(true);
            return false;
        });
        history_overlay.leave_notify_event.connect((event) => {
            history_copy_revealer.set_reveal_child(false);
            return false;
        });
        notebook.append_page(history_overlay, new Label("Connection History"));

        content.pack_start(notebook, true, true, 0);

        this.logs_dialog.response.connect((response_id) => {
            this.logs_dialog.hide();
        });

        this.logs_dialog.delete_event.connect((event) => {
            this.logs_dialog.hide();
            return true;
        });

        this.logs_dialog.show_all();
        this.logs_dialog.hide();
    }

    private void on_view_logs() {
        this.logs_dialog.show_all();
        this.logs_dialog.present();
    }

    private Revealer create_floating_copy_button(TextView source_view, string tooltip_text) {
        var revealer = new Revealer();
        revealer.set_transition_type(RevealerTransitionType.CROSSFADE);
        revealer.set_transition_duration(150);
        revealer.set_reveal_child(false);
        revealer.set_halign(Align.END);
        revealer.set_valign(Align.START);
        revealer.set_margin_top(10);
        revealer.set_margin_end(10);

        var copy_btn = new Button();
        copy_btn.set_tooltip_text(tooltip_text);
        copy_btn.set_image(new Image.from_icon_name("edit-copy-symbolic", IconSize.BUTTON));
        copy_btn.set_relief(ReliefStyle.NORMAL);
        copy_btn.clicked.connect(() => {
            copy_text_view_to_clipboard(source_view);
        });

        revealer.add(copy_btn);
        return revealer;
    }

    private void copy_text_view_to_clipboard(TextView view) {
        TextIter start_iter;
        TextIter end_iter;
        var buffer = view.get_buffer();
        buffer.get_start_iter(out start_iter);
        buffer.get_end_iter(out end_iter);
        string text = buffer.get_text(start_iter, end_iter, false);
        var clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(text, -1);
    }

    private void update_status(string text, string icon_name, string color_hex) {
        this.status_label.set_markup("<span weight='bold' foreground='%s'>%s</span>".printf(color_hex, Markup.escape_text(text, -1)));
        this.status_icon.set_from_icon_name(icon_name, IconSize.BUTTON);
    }

    private void update_config_label() {
        if (this.vpn_manager.config_file == "") {
            this.config_label.set_text("No configuration file selected");
        } else {
            this.config_label.set_text(this.vpn_manager.config_file);
        }
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
            update_config_label();
            append_output("Auto-loaded configuration file: %s\n".printf(last_config));
        }
    }

    private bool detect_active_vpn_on_startup() {
        string active_session_path;
        if (openvpn3_has_connected_session_for_config(out active_session_path)) {
            this.vpn_manager.session_path = active_session_path;
            return true;
        }

        return false;
    }

    private string get_path_from_openvpn3_block(string block_text) {
        var lines = block_text.split("\n");
        foreach (string line in lines) {
            if (line.contains("Path:")) {
                var parts = line.split("Path:");
                if (parts.length > 1) {
                    return parts[1].strip();
                }
            }
        }
        return "";
    }

    private bool openvpn3_has_connected_session_for_config(out string found_session_path) {
        found_session_path = "";

        try {
            string stdout_str;
            string stderr_str;
            int exit_status;

            Process.spawn_command_line_sync(
                "openvpn3 sessions-list",
                out stdout_str,
                out stderr_str,
                out exit_status
            );

            if (exit_status != 0 || stdout_str.strip() == "" || stdout_str.contains("No sessions available")) {
                return false;
            }

            var blocks = stdout_str.split("-----------------------------------------------------------------------------");
            foreach (string block in blocks) {
                if (!block.contains("Status: Connection, Client connected")) {
                    continue;
                }

                if (this.vpn_manager.config_file != "" && !block.contains("Config name: " + this.vpn_manager.config_file)) {
                    continue;
                }

                found_session_path = get_path_from_openvpn3_block(block);
                return true;
            }
        } catch (Error e) {
            // Treat errors as no connected session.
        }

        return false;
    }

    private bool openvpn3_session_still_connected(string session_path) {
        if (session_path == "") {
            return false;
        }

        try {
            string stdout_str;
            string stderr_str;
            int exit_status;

            Process.spawn_command_line_sync(
                "openvpn3 sessions-list",
                out stdout_str,
                out stderr_str,
                out exit_status
            );

            if (exit_status != 0 || stdout_str.strip() == "" || stdout_str.contains("No sessions available")) {
                return false;
            }

            var blocks = stdout_str.split("-----------------------------------------------------------------------------");
            foreach (string block in blocks) {
                if (!block.contains("Path: " + session_path)) {
                    continue;
                }
                return block.contains("Status: Connection, Client connected");
            }
        } catch (Error e) {
            return false;
        }

        return false;
    }

    private void check_and_update_connection_status() {
        if (detect_active_vpn_on_startup()) {
            this.vpn_manager.connected = true;
            update_status("Connected", "network-vpn-symbolic", "#1f7a3d");
            this.disconnect_btn.set_sensitive(true);
            this.connect_btn.set_sensitive(false);
            append_output("Detected active VPN connection on startup.\n");
        } else {
            this.vpn_manager.connected = false;
            update_status("Disconnected", "network-offline-symbolic", "#6b7280");

            // VPN is not connected - enable connect button if config is loaded
            if (this.vpn_manager.config_file != "") {
                this.connect_btn.set_sensitive(true);
            }
            this.disconnect_btn.set_sensitive(false);
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
            update_status("Connected", "network-vpn-symbolic", "#1f7a3d");
            this.disconnect_btn.set_sensitive(true);
            this.connect_btn.set_sensitive(false);
            if (text.contains("VPN Connected Successfully")) {
                append_history("Connected");
            }
        } else if (text.contains("Process exited")) {
            update_status("Disconnected", "network-offline-symbolic", "#6b7280");
            this.disconnect_btn.set_sensitive(false);
            if (this.vpn_manager.config_file != "") {
                this.connect_btn.set_sensitive(true);
            }
        }
    }

    private void on_error(string error) {
        append_output("ERROR: " + error + "\n");
        update_status("Connection Failed", "dialog-error-symbolic", "#b42318");
        this.connect_btn.set_sensitive(true);
        this.disconnect_btn.set_sensitive(false);
        append_history("Connection failed: " + error);
    }

    private void on_connect() {
        this.connect_btn.set_sensitive(false);
        update_status("Connecting...", "network-transmit-receive-symbolic", "#9a6700");
        append_output("\n=== Connecting to VPN ===\n");
        append_history("Attempting connection...");

        this.vpn_manager.connect();
    }

    private void on_disconnect() {
        this.disconnect_btn.set_sensitive(false);
        this.disconnect_verify_attempts = 0;
        this.vpn_manager.disconnect();
        
        // Give the system a moment to process the kill command
        Timeout.add(500, () => {
            verify_disconnection();
            return false;
        });
    }
    
    private void verify_disconnection() {
        try {
            bool still_connected;
            if (this.vpn_manager.session_path != "") {
                still_connected = openvpn3_session_still_connected(this.vpn_manager.session_path);
            } else {
                string found_path;
                still_connected = openvpn3_has_connected_session_for_config(out found_path);
                if (still_connected && found_path != "") {
                    this.vpn_manager.session_path = found_path;
                }
            }

            if (!still_connected) {
                this.vpn_manager.connected = false;
                this.vpn_manager.session_path = "";
                update_status("Disconnected", "network-offline-symbolic", "#6b7280");
                this.disconnect_btn.set_sensitive(false);
                if (this.vpn_manager.config_file != "") {
                    this.connect_btn.set_sensitive(true);
                }
                append_history("Disconnected");
                append_output("✓ VPN Disconnected\n");
            } else {
                append_output("VPN session still active, retrying disconnect check...\n");
                this.disconnect_verify_attempts++;
                if (this.disconnect_verify_attempts < 10) {
                    Timeout.add(500, () => {
                        verify_disconnection();
                        return false;
                    });
                } else {
                    append_output("Disconnect is taking longer than expected.\n");
                    update_status("Disconnecting...", "network-transmit-receive-symbolic", "#9a6700");
                    if (this.vpn_manager.config_file != "") {
                        this.connect_btn.set_sensitive(true);
                    }
                }
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
            update_config_label();
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
