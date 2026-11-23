#!/usr/bin/python3
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gio, GLib, Gtk

# The CLI and launcher share the same installation prefix (user or system).
CONTROL = str(Path(__file__).resolve().parents[2] / "bin/speaker-bass")


class SwitchWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Speaker Bass")
        self.set_default_size(340, -1)
        self.busy = False
        self.updating = False
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for side in ("top", "bottom", "start", "end"):
            setattr(panel.props, "margin_" + side, 20)
        self.set_child(panel)

        row = Gtk.Box(spacing=20)
        panel.append(row)
        label = Gtk.Label(label="_Bass enhancement", use_underline=True,
                          xalign=0, hexpand=True)
        row.append(label)
        self.switch = Gtk.Switch(valign=Gtk.Align.CENTER, sensitive=False)
        label.set_mnemonic_widget(self.switch)
        row.append(self.switch)
        self.status = Gtk.Label(label="Checking built-in speakers…", wrap=True,
                                xalign=0, max_width_chars=45)
        panel.append(self.status)
        self.retry = Gtk.Button(label="Check again", halign=Gtk.Align.START,
                                visible=False)
        panel.append(self.retry)
        self.retry.connect("clicked", lambda *_: self.run_control("status"))
        self.switch.connect("state-set", self.request_change)
        self.connect("notify::is-active", self.focus_changed)
        self.run_control("status")

    def focus_changed(self, *_):
        if self.is_active():
            self.run_control("status")

    def request_change(self, _, active):
        if self.updating:
            return False
        self.run_control("on" if active else "off")
        return True

    def run_control(self, action):
        if self.busy:
            return
        self.busy = True
        self.switch.set_sensitive(False)
        self.retry.set_visible(False)
        try:
            flags = Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
            proc = Gio.Subprocess.new([CONTROL, action], flags)
            proc.communicate_utf8_async(None, None, self.read_result)
        except GLib.Error as error:
            self.show_error(error.message)

    def read_result(self, proc, result):
        try:
            _, out, err = proc.communicate_utf8_finish(result)
        except GLib.Error as error:
            self.show_error(error.message)
            return
        state = (out or "").strip()
        if not proc.get_successful() or state not in ("Speaker bass ON", "Speaker bass OFF"):
            self.show_error((err or "").strip() or state or "Could not read the speaker setting.")
            return
        active = state == "Speaker bass ON"
        self.updating = True
        self.switch.set_active(active)
        self.switch.set_state(active)
        self.updating = False
        self.switch.set_visible(True)
        self.switch.set_sensitive(True)
        self.status.set_text("Built-in speakers · " + ("On" if active else "Off"))
        self.busy = False

    def show_error(self, message):
        self.busy = False
        self.switch.set_visible(False)
        self.status.set_text(message)
        self.retry.set_visible(True)


def activate(app):
    window = app.get_active_window() or SwitchWindow(app)
    window.present()


if __name__ == "__main__":
    GLib.set_application_name("Speaker Bass")
    application = Gtk.Application(application_id="local.speaker.Bass")
    application.connect("activate", activate)
    raise SystemExit(application.run(None))
