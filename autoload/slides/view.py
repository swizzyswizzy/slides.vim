#!/usr/bin/env python3
"""Fullscreen image viewer for slides.vim.

Writes a one-line command (next/prev/quit) to --cmd and exits.
Keys: n Space Right = next; N Left BackSpace = prev; q Escape = quit.
"""
from __future__ import print_function

import argparse
import os
import sys


def write_cmd(path, name):
    if not path:
        return
    directory = os.path.dirname(path)
    if directory and not os.path.isdir(directory):
        os.makedirs(directory)
    with open(path, "w") as handle:
        handle.write(name + "\n")


def finish(cmd_path, name):
    write_cmd(cmd_path, name)
    sys.exit(0)


def run_gtk(image_path, cmd_path):
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk, Gdk, GdkPixbuf

    win = Gtk.Window()
    win.set_title("slides-current")
    win.fullscreen()
    win.set_keep_above(True)
    win.modify_bg(Gtk.StateType.NORMAL, Gdk.Color(0, 0, 0))

    screen = win.get_screen()
    try:
        mon = screen.get_monitor_geometry(0)
        max_w, max_h = mon.width, mon.height
    except Exception:
        max_w, max_h = 1920, 1080

    pix = GdkPixbuf.Pixbuf.new_from_file(image_path)
    pw, ph = pix.get_width(), pix.get_height()
    scale = min(float(max_w) / max(pw, 1), float(max_h) / max(ph, 1))
    nw, nh = max(1, int(pw * scale)), max(1, int(ph * scale))
    if (nw, nh) != (pw, ph):
        pix = pix.scale_simple(nw, nh, GdkPixbuf.InterpType.BILINEAR)

    img = Gtk.Image.new_from_pixbuf(pix)
    box = Gtk.EventBox()
    box.modify_bg(Gtk.StateType.NORMAL, Gdk.Color(0, 0, 0))
    box.add(img)
    win.add(box)

    def on_key(_widget, event):
        key = Gdk.keyval_name(event.keyval) or ""
        key = key.lower()
        if key in ("n", "space", "right"):
            finish(cmd_path, "next")
        elif key in ("n",) and event.state & Gdk.ModifierType.SHIFT_MASK:
            finish(cmd_path, "prev")
        elif key in ("left", "backspace"):
            finish(cmd_path, "prev")
        elif key in ("q", "escape"):
            finish(cmd_path, "quit")
        return True

    # Shift+n comes through as 'N'
    def on_key2(_widget, event):
        raw = Gdk.keyval_name(event.keyval) or ""
        if raw == "N":
            finish(cmd_path, "prev")
            return True
        return on_key(_widget, event)

    win.connect("key-press-event", on_key2)
    win.connect("destroy", lambda *_: finish(cmd_path, "quit"))
    win.show_all()
    win.present()
    Gtk.main()


def run_tk(image_path, cmd_path):
    try:
        from PIL import Image, ImageTk
        use_pil = True
    except Exception:
        Image = ImageTk = None
        use_pil = False

    import tkinter as tk

    root = tk.Tk()
    root.title("slides-current")
    root.configure(bg="black")
    root.attributes("-fullscreen", True)
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass
    root.config(cursor="none")

    sw = root.winfo_screenwidth()
    sh = root.winfo_screenheight()

    photo = None
    if use_pil:
        im = Image.open(image_path)
        im.thumbnail((sw, sh), Image.LANCZOS)
        photo = ImageTk.PhotoImage(im)
    else:
        photo = tk.PhotoImage(file=image_path)

    lbl = tk.Label(root, image=photo, bg="black")
    lbl.image = photo
    lbl.pack(expand=True)

    def bind(seq, name):
        root.bind(seq, lambda e: (write_cmd(cmd_path, name), root.destroy()))

    bind("<n>", "next")
    bind("<space>", "next")
    bind("<Right>", "next")
    bind("<N>", "prev")
    bind("<Left>", "prev")
    bind("<BackSpace>", "prev")
    bind("<q>", "quit")
    bind("<Escape>", "quit")
    root.protocol("WM_DELETE_WINDOW", lambda: (write_cmd(cmd_path, "quit"), root.destroy()))
    root.focus_force()
    root.mainloop()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("--cmd", default="")
    args = parser.parse_args()
    if not os.path.isfile(args.image):
        print("missing image", args.image, file=sys.stderr)
        sys.exit(2)

    errors = []
    try:
        run_gtk(args.image, args.cmd)
        return
    except Exception as exc:
        errors.append("gtk: %s" % exc)
    try:
        run_tk(args.image, args.cmd)
        return
    except Exception as exc:
        errors.append("tk: %s" % exc)
    print("slides-view failed: " + " | ".join(errors), file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
