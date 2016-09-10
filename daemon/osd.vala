/*
 * This file is part of budgie-desktop
 * 
 * Copyright (C) 2016 Ikey Doherty <ikey@solus-project.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

namespace Budgie
{

/**
 * Default width for an OSD notification
 */
public static const int OSD_SIZE = 250;

/**
 * Our name on the session bus. Reserved for Budgie use
 */
public static const string OSD_DBUS_NAME        = "com.solus_project.BudgieOSD";

/**
 * Unique object path on OSD_DBUS_NAME
 */
public static const string OSD_DBUS_OBJECT_PATH = "/com/solus_project/BudgieOSD";


/**
 * The BudgieOSD provides a very simplistic On Screen Display service, complying with the
 * private GNOME Settings Daemon -> GNOME Shell protocol.
 *
 * In short, all elements of the permanently present window should be able to hide or show
 * depending on the updated ShowOSD message, including support for a progress bar (level),
 * icon, optional label.
 *
 * This OSD is used by gnome-settings-daemon to portray special events, such as brightness/volume
 * changes, physical volume changes (disk eject/mount), etc. This special window should remain
 * above all other windows and be non-interactive, allowing unobtrosive overlay of information
 * even in full screen movies and games.
 *
 * Each request to ShowOSD will reset the expiration timeout for the OSD's current visibility,
 * meaning subsequent requests to the OSD will keep it on screen in a natural fashion, allowing
 * users to "hold down" the volume change buttons, for example.
 */
[GtkTemplate (ui = "/com/solus-project/budgie/daemon/osd.ui")]
public class OSD : Gtk.Window
{

    /**
     * Main text display
     */
    [GtkChild]
    private Gtk.Label label_title;

    /**
     * Main display image. Prefer symbolic icons!
     */
    [GtkChild]
    private Gtk.Image image_icon;

    /**
     * Optional progressbar
     */
    [GtkChild]
    private Gtk.ProgressBar progressbar;

    /**
     * Current text to display. NULL hides the widget.
     */
    public string? osd_title {
        public set {
            string? r = value;
            if (r == null) {
                label_title.set_visible(false);
            } else {
                label_title.set_visible(true);
                label_title.set_markup(r);
            }
        }
        public owned get {
            if (!label_title.get_visible()) {
                return null;
            }
            return label_title.get_label();
        }
    }

    /**
     * Current icon to display. NULL hides the widget
     */
    public string? osd_icon {
        public set {
            string? r = value;
            if (r == null) {
                image_icon.set_visible(false);
            } else {
                image_icon.set_from_icon_name(r, Gtk.IconSize.INVALID);
                image_icon.pixel_size = 32;
                image_icon.set_visible(true);
            }
        }
        public owned get {
            if (!image_icon.get_visible()) {
                return null;
            }
            string ret;
            Gtk.IconSize _icon_size;
            image_icon.get_icon_name(out ret, out _icon_size);
            return ret;
        }
    }

    /**
     * Current value for the progressbar. Values less than 1 hide the bar
     */
    public int32 osd_progress {
        public set {
            int32 v = value;
            if (v < 0) {
                progressbar.set_visible(false);
            } else {
                double fraction = v.clamp(0, 100) / 100.0;
                progressbar.set_fraction(fraction);
                progressbar.set_visible(true);
            }
        }
        public get {
            if (!progressbar.get_visible()) {
                return -1;
            } else {
                return (int32)(progressbar.get_fraction() * 100);
            }
        }
    }

    /**
     * Construct a new BudgieOSD widget
     */
    public OSD()
    {
        Object(type: Gtk.WindowType.POPUP, type_hint: Gdk.WindowTypeHint.NOTIFICATION);
        /* Skip everything, appear above all else, everywhere. */
        resizable = false;
        skip_pager_hint = true;
        skip_taskbar_hint = true;
        set_decorated(false);
        set_keep_above(true);
        stick();

        /* Set up an RGBA map for transparency styling */
        Gdk.Visual? vis = screen.get_rgba_visual();
        if (vis != null) {
            this.set_visual(vis);
        }

        /* Set up size */
        set_default_size(OSD_SIZE, -1);
        realize();
        move_osd();

        osd_title = null;
        osd_icon = null;
        osd_progress = -1;

        /* Temp! */
        show_all();
    }

    /**
     * Move the OSD into the correct position
     */
    private void move_osd()
    {
        /* Find the primary monitor bounds */
        Gdk.Screen sc = get_screen();
        int monitor = sc.get_primary_monitor();
        Gdk.Rectangle bounds;

        sc.get_monitor_geometry(monitor, out bounds);
        Gtk.Allocation alloc;

        get_allocation(out alloc);

        /* For now just center it */
        int x = bounds.x + ((bounds.width / 2) - (alloc.width / 2));
        int y = bounds.y + ((int)(bounds.height * 0.85));
        move(x, y);
    }
} /* End class OSD (BudgieOSD) */

/**
 * BudgieOSDManager is responsible for managing the BudgieOSD over d-bus, recieving
 * requests, for example, from budgie-wm
 */
[DBus (name = "com.solus_project.BudgieOSD")]
public class OSDManager
{
    private OSD? osd_window = null;

    [DBus (visible = false)]
    public OSDManager()
    {
        osd_window = new OSD();
    }

    /**
     * Own the OSD_DBUS_NAME
     */
    [DBus (visible = false)]
    public void setup_dbus()
    {
        Bus.own_name(BusType.SESSION, Budgie.OSD_DBUS_NAME, BusNameOwnerFlags.ALLOW_REPLACEMENT|BusNameOwnerFlags.REPLACE,
            on_bus_acquired, ()=> {}, ()=> { warning("BudgieOSD could not take dbus!"); });
    }

    /**
     * Acquired OSD_DBUS_NAME, register ourselves on the bus
     */
    private void on_bus_acquired(DBusConnection conn)
    {
        try {
            conn.register_object(Budgie.OSD_DBUS_OBJECT_PATH, this);
        } catch (Error e) {
            stderr.printf("Error registering BudgieOSD: %s\n", e.message);
        }
    }

    /**
     * Show the OSD on screen with the given parameters:
     * icon: string Icon-name to use
     * label: string Text to display, if any
     * level: int32 Progress-level to display in the OSD
     * monitor: int32 The monitor to display the OSD on
     */
    public void ShowOSD(HashTable<string,Variant> params)
    {
        string? icon_name = null;
        string? label = null;
        int32 level = -1;

        if (params.contains("icon")) {
            icon_name = params.lookup("icon").get_string();
        }
        if (params.contains("label")) {
            label = params.lookup("label").get_string();
        }
        if (params.contains("level")) {
            level = params.lookup("level").get_int32();
        }
        /* Update the OSD accordingly */
        osd_window.osd_title = label;
        osd_window.osd_icon = icon_name;
        osd_window.osd_progress = level;

        /*
        if (params.contains("monitor")) {
            int32 monitor = params.lookup("monitor").get_int32();
            message("monitor: %d", monitor);
        }*/
    }
} /* End class OSDManager (BudgieOSDManager) */

} /* End namespace Budgie */
