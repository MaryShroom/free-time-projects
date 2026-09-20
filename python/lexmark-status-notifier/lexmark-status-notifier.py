import sys
import logging
import traceback
import threading
import subprocess
from pathlib import Path
import requests
import socket
import json
import tkinter as tk
from tkinter import ttk, messagebox
from PIL import Image, ImageDraw
import pystray
from pystray import MenuItem as item
import webbrowser
from datetime import datetime

# Import GTK bindings
try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk
    HAS_GTK = True
except (ImportError, ValueError):
    HAS_GTK = False

# Global Variables
FILE_NAME = Path(__file__)
APP_NAME = "Lexmark Status Notifier"
STATUS_COLORS = {
    "ok": (0, 255, 0, 255),
    "warning": (255, 255, 0, 255),
    "critical": (255, 0, 0, 255),
    "default": (128, 128, 128, 255)
}
CONFIG_DIR = Path.home() / ".config" / Path(__file__).stem
LOG_FILE = CONFIG_DIR / "error.log"

# --- Logging System ---
# Simple popup message
def show_message(title, message, message_type="info"):
    if message_type == "info":
        messagebox.showinfo(title, message)
    elif message_type == "warning":
        messagebox.showwarning(title, message)
    elif message_type == "error":
        messagebox.showerror(title, message)

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.ERROR,
    format="%(asctime)s [%(levelname)s] (%(threadName)s = %(message)s)",
    datefmt="%d-%m-%Y %H:%M:%S",
)

def handle_main_exception(exc_type, exc_value, exc_traceback):
    if issubclass(exc_type, KeyboardInterrupt):
        sys.__excepthook__(exc_type, exc_value, exc_traceback)
        return
    logging.error("Unhandled exception in Main Thread:", exc_info=(exc_type, exc_value, exc_traceback))
    show_message("Application Error", f"An unexpected main thread error occured:\n\n{exc_value}", "error")

sys.excepthook = handle_main_exception

def handle_thread_exception(args):
    logging.error(
        f"Unhandled exception in thread '{args.thread.name}':",
        exc_info=(args.exc_type, args.exc_value, args.exc_traceback)
    )
    show_message("Background Thread Error", f"An unexpected background error occured in '{args.thread.name}':\n\n{args.exc_value}", "error")

threading.excepthook = handle_thread_exception

# --- End Logging System ---

def notify_normal(title, message):
    try:
        subprocess.run([
            "notify-send",
            "-a", APP_NAME,
            title, message
        ], check=True)
    except FileNotFoundError:
        sys.stdout.write(f"ALERT: {title} - {message}\n")

def notify_urgent(title, message):
    try:
        subprocess.run([
            "notify-send",
            "-a", APP_NAME,
            "-u", "critical",
            "-i", "dialog-warning",
            title, message
        ], check=True)
    except FileNotFoundError:
        sys.stderr.write(f"ALERT: {title} - {message}\n")

def status_icon(status="default"):
    # Tray Icon
    color = STATUS_COLORS.get(status, STATUS_COLORS["default"])
    image = Image.new('RGBA', (64, 64), color=(0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((8,8,56,56), fill=color)
    draw.ellipse((24,24,40,40), fill=(0, 0, 0, 0))
    return image

class ConfigHandler:
    def __init__(self):
        # Default value for printers' JSON
        self._default_data = {
            "notify_times": ["08:00:00", "20:00:00"],
            "timer_minutes": 30,
            "printers": {}
        }
        self._default_protocol = "http://"
        self._default_endpoint = "/webglue/rawcontent?c=Status&lang=en"

        # .config path and printers' JSON file
        self.printers_json = CONFIG_DIR / f"printers.json"
        self._create_dir_and_json()

    def _create_dir_and_json(self):
        # Check inside .config exist
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        # Create printers' JSON if not exist
        if not Path(self.printers_json).exists():
            try:
                with open(self.printers_json, "w", encoding="utf-8") as file:
                    json.dump(self._default_data, file, indent=4)
            except OSError as e:
                sys.stderr.write(f"Error writing file '{self.printers_json}': {e}\n")

        # Read exists JSON
        try:
            with open(self.printers_json, "r", encoding="utf-8") as file:
                self.data = json.load(file)
        except json.JSONDecodeError:
            try:
                with open(self.printers_json, "w", encoding="utf-8") as file:
                    json.dump(self._default_data, file, indent=4)
                self.data = self._default_data
            except OSError as e:
                sys.stderr.write(f"Error writing file '{self.printers_json}': {e}\n")
        except OSError as e:
            sys.stderr.write(f"Error writing file '{self.printers_json}': {e}\n")

    def update_to_file(self):
        try:
            with open(self.printers_json, "w", encoding="utf-8") as file:
                json.dump(self.data, file, indent=4)
        except OSError as e:
            sys.stderr.write(f"Error writing file '{self.printers_json}': {e}\n")

    def set_notify_times(self, notify_times=["08:00:00", "20:00:00"]):
        self.data["notify_times"] = notify_time
        return True

    def get_notify_times(self):
        return self.data.get("notify_times", ["08:00:00", "20:00:00"])

    def set_timer(self, time_min=30):
        self.data["timer_minutes"] = int(time_min)
        return True

    def get_timer(self):
        return self.data.get("timer_minutes", 30)

    def add_printer(self,
                    ip,
                    name="N/A",
                    serial="N/A",
                    location="N/A",
                    protocol=None,
                    endpoint=None,
                    available=False,
                    toner_lvl="N/A",
                    toner_s="N/A",
                    image_lvl="N/A",
                    image_s="N/A",
                    maint_lvl="N/A",
                    maint_s="N/A",
                    bottle_lvl="N/A",
                    bottle_s="N/A"):
        if protocol is None:
            protocol = self._default_protocol
        if endpoint is None:
            endpoint = self._default_endpoint
        self.data["printers"][ip] = {
            "name": name,
            "serial": serial,
            "location": location,
            "protocol": protocol,
            "endpoint": endpoint,
            "available": available,
            "supplies": {
                "toner_level": toner_lvl,
                "toner_status": toner_s,
                "image_level": image_lvl,
                "image_status": image_s,
                "maint_level": maint_lvl,
                "maint_status": maint_s,
                "bottle_level": bottle_lvl,
                "bottle_status": bottle_s
            }
        }
        return True

    def remove_printer(self, ip):
        self.data["printers"].pop(ip, None)
        return True

    def set_printer(self,
                    ip,
                    name=None,
                    serial=None,
                    location=None,
                    protocol=None,
                    endpoint=None,
                    available=None,
                    toner_lvl=None,
                    toner_s=None,
                    image_lvl=None,
                    image_s=None,
                    maint_lvl=None,
                    maint_s=None,
                    bottle_lvl=None,
                    bottle_s=None):
        if available is None:
            available = self.data["printers"][ip]["available"]
        self.data["printers"][ip] = {
            "name": name or self.data["printers"][ip]["name"],
            "serial": serial or self.data["printers"][ip]["serial"],
            "location": location or self.data["printers"][ip]["location"],
            "protocol": protocol or self.data["printers"][ip]["protocol"],
            "endpoint": endpoint or self.data["printers"][ip]["endpoint"],
            "available": available,
            "supplies": {
                "toner_level": toner_lvl or self.data["printers"][ip]["supplies"]["toner_level"],
                "toner_status": toner_s or self.data["printers"][ip]["supplies"]["toner_status"],
                "image_level": image_lvl or self.data["printers"][ip]["supplies"]["image_level"],
                "image_status": image_s or self.data["printers"][ip]["supplies"]["image_status"],
                "maint_level": maint_lvl or self.data["printers"][ip]["supplies"]["maint_level"],
                "maint_status": maint_s or self.data["printers"][ip]["supplies"]["maint_status"],
                "bottle_level": bottle_lvl or self.data["printers"][ip]["supplies"]["bottle_level"],
                "bottle_status": bottle_s or self.data["printers"][ip]["supplies"]["bottle_status"]
            }
        }
        return True

    def get_printers(self):
        return self.data.get("printers", {})

    def get_printer(self, ip):
        return self.data.get("printers", {}).get(ip, {})

    def set_availability(self, ip, value):
        self.data["printers"][ip]["available"] = value
        return True

    def get_availability(self, ip):
        return self.data["printers"][ip]["available"]

class PrinterStatusHandler():
    def __init__(self, protocol, ip, endpoint):
        self.protocol = protocol
        self.ip = ip
        self.endpoint = endpoint

        # Offline Default
        self.serial = "N/A"
        self.status = False
        self.supplies = {
            "toner_level": "N/A",
            "toner_status": "N/A",
            "image_level": "N/A",
            "image_status": "N/A",
            "maint_level": "N/A",
            "maint_status": "N/A",
            "bottle_level": "N/A",
            "bottle_status": "N/A"
        }

    def fetch_data(self):
        # Try fetch data from printer
        try:
            target_url = f"{self.protocol}{self.ip}{self.endpoint}"
            response = requests.get(target_url, timeout=5)
            response.raise_for_status()
            self.status = True
            self.serial = response.json()["nodes"]["nodes"]["DeviceSerialNumberLxk"]["text"]["text"]
            self.supplies = {
                "toner_level": response.json()["nodes"]["supplies"].get("Black Toner", {}).get("curlevel", "N/A"),
                "toner_status": response.json()["nodes"]["supplies"].get("Black Toner", {}).get("currentStatus", "N/A"),
                "image_level": response.json()["nodes"]["supplies"].get("Black Imaging Kit", {}).get("curlevel", "N/A"),
                "image_status": response.json()["nodes"]["supplies"].get("Black Imaging Kit", {}).get("currentStatus", "N/A"),
                "maint_level": response.json()["nodes"]["supplies"].get("Maintenance Kit", {}).get("curlevel", "N/A"),
                "maint_status": response.json()["nodes"]["supplies"].get("Maintenance Kit", {}).get("currentStatus", "N/A"),
                "bottle_level": response.json()["nodes"]["supplies"].get("Toner Bottle", {}).get("curlevel", "N/A"),
                "bottle_status": response.json()["nodes"]["supplies"].get("Toner Bottle", {}).get("currentStatus", "N/A")
            }
        except requests.exceptions.RequestException:
            self.status = False
        return None

    def get_status(self):
        return self.status

    def get_serial(self):
        return self.serial

    def get_supplies(self):
        return self.supplies

class PopupMessage(tk.Toplevel):
    def __init__(self, parent, title, message, buttons):
        super().__init__(parent)
        self.result = None
        self.title(title)
        self.configure(bg="#F0F0F0", padx=20, pady=20)
        self.resizable(False, False)

        # Message
        msg = tk.Label(
            self,
            text=message,
            bg="#F0F0F0",
            fg="#000000",
            font=("Monospace", 10),
            wraplength=300,
            justify="center"
        )
        msg.pack(padx=10, pady=(0, 20))

        btn_frame = tk.Frame(self, bg="#F0F0F0")
        btn_frame.pack(fill="x", expand=True)

        for text, value, bg_value, abg_value in buttons:
            if bg_value is None:
                bg_value = "#F0F0F0"

            if abg_value is None:
                abg_value = "#FAFAFA"

            btn = tk.Button(
                btn_frame,
                text=text,
                bg=bg_value,
                fg="#000000",
                activebackground=abg_value,
                activeforeground="#000000",
                relief="flat",
                padx=12,
                pady=6,
                command=lambda v=value: self._on_click(v)
            ).pack(side="left", expand=True, padx=5)


        self.transient(parent)
        self.grab_set()

        self._center_window(parent)
        self.wait_window()

    def _on_click(self, value):
        self.result = value
        self.destroy()

    def _center_window(self, parent):
        self.update_idletasks()
        p_x = parent.winfo_rootx()
        p_y = parent.winfo_rooty()
        p_w = parent.winfo_width()
        p_h = parent.winfo_height()

        w = self.winfo_width()
        h = self.winfo_height()

        x = p_x + (p_w // 2) - (w // 2)
        y = p_y + (p_h // 2) - (h // 2)
        self.geometry(f"+{x}+{y}")

class ListRowObject:
    def __init__(self, parent_frame, printer_items, supplies, on_config, on_web, on_remove, warning_level, radius=12, bg_color="#F0F0F0", border_color="#D0D0D0"):
        self.parent_frame = parent_frame

        # Printer information
        self.printer_items = printer_items
        self.supplies = supplies
        self.warning_level = warning_level[4]
        self.critical_level = warning_level[1]

        self.radius = radius
        self.bg_color = bg_color
        self.border_color = border_color
        self.on_remove = on_remove

        if self.printer_items["available"]:
            self.ip_fg = "#008F00"
        else:
            self.ip_fg = "#8F0000"

        # Rounded Canvas
        self.canvas = tk.Canvas(
            parent_frame,
            height=186,
            bg=self.bg_color,
            highlightthickness=0
        )
        self.canvas.pack(fill="x", expand=True, pady=4, padx=5)

        self.rect_id = None
        self.canvas.bind("<Configure>", self._draw_rounded_rect)

        # IP Label
        self.ip_label = tk.Label(
            self.canvas,
            text=f"{self.printer_items['ip']}",
            anchor="nw",
            bg=self.bg_color,
            fg=self.ip_fg,
            font=("Monospace", 8),
            highlightthickness=0
        )
        # Name Location Label
        self.name_label = tk.Label(
            self.canvas,
            text=f"{self.printer_items['name']} ({self.printer_items['location']})",
            anchor="nw",
            bg=self.bg_color,
            fg="#000000",
            font=("Monospace", 16),
            highlightthickness=0
        )
        # Serial Number Label
        self.serial_label = tk.Label(
            self.canvas,
            text=f"{self.printer_items['serial']}",
            anchor="nw",
            bg=self.bg_color,
            fg="#000000",
            font=("Monospace", 8),
            highlightthickness=0
        )

        # --- Supplies Status ---
        self.prog_style = ttk.Style()
        self.prog_style.theme_use('clam')
        self.prog_style.configure(
            "Ok.Horizontal.TProgressbar",
            troughcolor=self.bg_color,
            background="#008F00",
            border_color=self.bg_color,
            lightcolor="#008F00",
            darkcolor="#008F00",
            paddings=0,
            borderwidth=0
        )
        self.prog_style.configure(
            "Warn.Horizontal.TProgressbar",
            troughcolor=self.bg_color,
            background="#8F8F00",
            border_color=self.bg_color,
            lightcolor="#8F8F00",
            darkcolor="#8F8F00",
            paddings=0,
            borderwidth=0
        )
        self.prog_style.configure(
            "Crit.Horizontal.TProgressbar",
            troughcolor=self.bg_color,
            background="#8F0000",
            border_color=self.bg_color,
            lightcolor="#8F0000",
            darkcolor="#8F0000",
            paddings=0,
            borderwidth=0
        )
        # Toner
        self.toner_label = tk.Label(
            self.canvas,
            text=f"Toner Level\t: {self.supplies['toner_level']}%\t[ {self.supplies['toner_status']} ]",
            anchor="nw",
            bg=self.bg_color,
            fg=self._get_fg_color(self.supplies['toner_status'], self.supplies['toner_level']),
            font=("Monospace", 10),
            padx=0,
            pady=0,
            bd=0,
            highlightthickness=0
        )
        if self.supplies['toner_level'] != "N/A":
            self.toner_prog = ttk.Progressbar(
                self.canvas,
                orient="horizontal",
                mode="determinate",
                style=self._get_style(self.supplies['toner_status'], self.supplies['toner_level']),
                value=self._get_value_na(self.supplies['toner_status'], self.supplies['toner_level']),
                maximum=100
            )
        else:
            self.toner_prog = tk.Frame(self.canvas, bg=self.bg_color, bd=0, highlightthickness=0)
        # Imaging Unit
        self.image_label = tk.Label(
            self.canvas,
            text=f"Imaging Unit\t: {self.supplies['image_level']}%\t[ {self.supplies['image_status']} ]",
            anchor="nw",
            bg=self.bg_color,
            fg=self._get_fg_color(self.supplies['image_status'], self.supplies['image_level']),
            font=("Monospace", 10),
            padx=0,
            pady=0,
            bd=0,
            highlightthickness=0
        )
        if self.supplies['image_level'] != "N/A":
            self.image_prog = ttk.Progressbar(
                self.canvas,
                orient="horizontal",
                mode="determinate",
                style=self._get_style(self.supplies['image_status'], self.supplies['image_level']),
                value=self._get_value_na(self.supplies['image_status'], self.supplies['image_level']),
                maximum=100
            )
        else:
            self.image_prog = tk.Frame(self.canvas, bg=self.bg_color, bd=0, highlightthickness=0)
        # Maintenance Kit
        self.maint_label = tk.Label(
            self.canvas,
            text=f"Maintenance Kit\t: {self.supplies['maint_level']}%\t[ {self.supplies['maint_status']} ]",
            anchor="nw",
            bg=self.bg_color,
            fg=self._get_fg_color(self.supplies['maint_status'], self.supplies['maint_level']),
            font=("Monospace", 10),
            padx=0,
            pady=0,
            bd=0,
            highlightthickness=0
        )
        if self.supplies['maint_level'] != "N/A":
            self.maint_prog = ttk.Progressbar(
                self.canvas,
                orient="horizontal",
                mode="determinate",
                style=self._get_style(self.supplies['maint_status'], self.supplies['maint_level']),
                value=self._get_value_na(self.supplies['image_status'], self.supplies['maint_level']),
                maximum=100
            )
        else:
            self.maint_prog = tk.Frame(self.canvas, bg=self.bg_color, bd=0, highlightthickness=0)
        # Bottle
        self.bottle_label = tk.Label(
            self.canvas,
            text=f"Waste Bottle\t: {self.supplies['bottle_level']}%\t[ {self.supplies['bottle_status']} ]",
            anchor="nw",
            bg=self.bg_color,
            fg=self._get_fg_color(self.supplies['bottle_status'], self.supplies['bottle_level']),
            font=("Monospace", 10),
            padx=0,
            pady=0,
            bd=0,
            highlightthickness=0
        )
        if self.supplies['bottle_level'] != "N/A":
            self.bottle_prog = ttk.Progressbar(
                self.canvas,
                orient="horizontal",
                mode="determinate",
                style=self._get_style(self.supplies['bottle_status'], self.supplies['bottle_level']),
                value=self._get_value_na(self.supplies['bottle_status'], self.supplies['bottle_level']),
                maximum=100
            )
        else:
            self.bottle_prog = tk.Frame(self.canvas, bg=self.bg_color, bd=0, highlightthickness=0)
        # --- End Supplies Status ---

        # Config Button
        self.config_button = tk.Button(
            self.canvas,
            text="Configure",
            bg="#9090F0",
            activebackground="#A0A0FF",
            relief="flat",
            padx=4,
            pady=4,
            command=lambda: on_config(self)
        )

        # Open Web Button
        self.web_button = tk.Button(
            self.canvas,
            text="Open Web",
            relief="flat",
            padx=4,
            pady=4,
            command=lambda: on_web(self.printer_items["protocol"], self.printer_items["ip"])
        )

        # Remove Button
        self.remove_button = tk.Button(
            self.canvas,
            text="Remove",
            bg="#F09090",
            activebackground="#FFA0A0",
            relief="flat",
            padx=4,
            pady=4,
            command=self.destroy
        )

        # Embed inside canvas
        self.canvas.create_window((10, 6), window=self.name_label, anchor="nw")
        self.canvas.create_window((10, 32), window=self.ip_label, anchor="nw")
        self.canvas.create_window((10, 45), window=self.serial_label, anchor="nw")

        self.canvas.create_window((10, 60), window=self.toner_label, anchor="nw")
        self.canvas.create_window((10, 90), window=self.image_label, anchor="nw")
        self.canvas.create_window((10, 120), window=self.maint_label, anchor="nw")
        self.canvas.create_window((10, 150), window=self.bottle_label, anchor="nw")

        self.toner_id = self.canvas.create_window((10, 76), window=self.toner_prog, anchor="nw", height=10)
        self.image_id = self.canvas.create_window((10, 106), window=self.image_prog, anchor="nw", height=10)
        self.maint_id = self.canvas.create_window((10, 136), window=self.maint_prog, anchor="nw", height=10)
        self.bottle_id = self.canvas.create_window((10, 166), window=self.bottle_prog, anchor="nw", height=10)

        self.canvas.create_window((0, 0), window=self.config_button, anchor="ne", tags="cfg_btn_window")
        self.canvas.create_window((0, 0), window=self.web_button, anchor="e", tags="web_btn_window")
        self.canvas.create_window((0, 0), window=self.remove_button, anchor="se", tags="rmv_btn_window")

    def _draw_rounded_rect(self, event):
        w, h = event.width, event.height
        r = self.radius

        if self.rect_id:
            self.canvas.delete(self.rect_id)

        points = [
            r, 2, w-r, 2, w-r, 2, w-2, 2, w-2, r, w-2, r, w-2, h-r,
            w-2, h-r, w-2, h-2, w-r, h-2, w-r, h-2, r, h-2, r, h-2,
            2, h-2, 2, h-r, 2, h-r, 2, r, 2, r, 2, 2, r, 2
        ]

        self.rect_id = self.canvas.create_polygon(
            points,
            smooth=True,
            fill=self.bg_color,
            outline=self.border_color,
            width=1
        )

        self.canvas.tag_lower(self.rect_id)

        # Progressbar Resize
        margin = 130
        new_width = max(10, event.width - margin)
        self.canvas.itemconfig(self.toner_id, width=new_width)
        self.canvas.itemconfig(self.image_id, width=new_width)
        self.canvas.itemconfig(self.maint_id, width=new_width)
        self.canvas.itemconfig(self.bottle_id, width=new_width)

        self.canvas.coords("cfg_btn_window", w - 10, 10)
        self.canvas.coords("web_btn_window", w - 10, h // 2)
        self.canvas.coords("rmv_btn_window", w - 10, h - 10)

    def _get_fg_color(self, available, value):
        if available == "N/A":
            return self.bg_color

        if value <= 5:
            return "#900000"
        elif value <= 20:
            return "#909000"

        return "#000000"

    def _get_value_na(self, available, value):
        if available == "N/A":
            return 100
        return value

    def _get_style(self, available, value):
        if available == "N/A":
            return "Crit.Horizontal.TProgressbar"

        if value <= 5:
            return "Crit.Horizontal.TProgressbar"
        elif value <= 20:
            return "Warn.Horizontal.TProgressbar"

        return "Ok.Horizontal.TProgressbar"

    def update_inside(self, new_printer_items, new_supplies):
        self.printer_items = new_printer_items
        self.supplies=new_supplies

        # Update Available Status
        if self.printer_items["available"]:
            self.ip_fg = "#00F000"
        else:
            self.ip_fg = "#F00000"

        # Update new data
        self.ip_label.config(text=self.printer_items["ip"], fg=self.ip_fg)
        self.name_label.config(text=f"{self.printer_items['name']} ({self.printer_items['location']})")
        self.serial_label.config(text=f"{self.printer_items['serial']}")

        self.toner_label.config(text=f"Toner Level\t: {self.supplies['toner_level']}%\t[ {self.supplies['toner_status']} ]")
        self.image_label.config(text=f"Imaging Unit\t: {self.supplies['image_level']}%\t[ {self.supplies['image_status']} ]")
        self.maint_label.config(text=f"Maintenance Kit\t: {self.supplies['maint_level']}%\t[ {self.supplies['maint_status']} ]")
        self.bottle_label.config(text=f"Waste Bottle\t: {self.supplies['bottle_level']}%\t[ {self.supplies['bottle_status']} ]")

        # Update colors
        self.toner_label.config(fg=self._get_fg_color(self.supplies['toner_status'], self.supplies['toner_level']))
        self.image_label.config(fg=self._get_fg_color(self.supplies['image_status'], self.supplies['image_level']))
        self.maint_label.config(fg=self._get_fg_color(self.supplies['maint_status'], self.supplies['maint_level']))
        self.bottle_label.config(fg=self._get_fg_color(self.supplies['bottle_status'], self.supplies['bottle_level']))

        # If not N/A and progressbar type, update progressbar
        if isinstance(self.toner_prog, ttk.Progressbar) and self.supplies['toner_level'] != "N/A":
            self.toner_prog.config(style=self._get_style(self.supplies['toner_status'], self.supplies['toner_level']))
        if isinstance(self.image_prog, ttk.Progressbar) and self.supplies['image_level'] != "N/A":
            self.image_prog.config(style=self._get_style(self.supplies['image_status'], self.supplies['image_level']))
        if isinstance(self.maint_prog, ttk.Progressbar) and self.supplies['maint_level'] != "N/A":
            self.maint_prog.config(style=self._get_style(self.supplies['maint_status'], self.supplies['maint_level']))
        if isinstance(self.bottle_prog, ttk.Progressbar) and self.supplies['bottle_level'] != "N/A":
            self.bottle_prog.config(style=self._get_style(self.supplies['bottle_status'], self.supplies['bottle_level']))

        # If not N/A and frame type, convert from frame to progressbar
        if isinstance(self.toner_prog, tk.Frame) and self.supplies['toner_level'] != "N/A":
            self.toner_prog.destroy()
            self.toner_prog = ttk.Progressbar(
                self.canvas,
                orient="horizontal",
                mode="determinate",
                style=self._get_style(self.supplies['toner_status'], self.supplies['toner_level']),
                value=self._get_value_na(self.supplies['toner_status'], self.supplies['toner_level']),
                maximum=100
            )
            self.canvas.itemconfigure(self.toner_id, window=self.toner_prog)
        if isinstance(self.image_prog, tk.Frame) and self.supplies['image_level'] != "N/A":
            self.image_prog.destroy()
            self.image_prog = ttk.Progressbar(
                self.canvas,
                orient="horizontal",
                mode="determinate",
                style=self._get_style(self.supplies['image_status'], self.supplies['image_level']),
                value=self._get_value_na(self.supplies['image_status'], self.supplies['image_level']),
                maximum=100
            )
            self.canvas.itemconfigure(self.image_id, window=self.image_prog)
        if isinstance(self.maint_prog, tk.Frame) and self.supplies['maint_level'] != "N/A":
            self.maint_prog.destroy()
            self.maint_prog = ttk.Progressbar(
                self.canvas,
                orient="horizontal",
                mode="determinate",
                style=self._get_style(self.supplies['maint_status'], self.supplies['maint_level']),
                value=self._get_value_na(self.supplies['image_status'], self.supplies['maint_level']),
                maximum=100
            )
            self.canvas.itemconfigure(self.maint_id, window=self.maint_prog)
        if isinstance(self.bottle_prog, tk.Frame) and self.supplies['bottle_level'] != "N/A":
            self.bottle_prog.destroy()
            self.bottle_prog = ttk.Progressbar(
                self.canvas,
                orient="horizontal",
                mode="determinate",
                style=self._get_style(self.supplies['bottle_status'], self.supplies['bottle_level']),
                value=self._get_value_na(self.supplies['bottle_status'], self.supplies['bottle_level']),
                maximum=100
            )
            self.canvas.itemconfigure(self.bottle_id, window=self.bottle_prog)

        # If N/A and progressbar type, convert progressbar to frame
        if isinstance(self.toner_prog, ttk.Progressbar) and self.supplies['toner_level'] == "N/A":
            self.toner_prog.destroy()
            self.toner_prog = tk.Frame(self.canvas, bg=self.bg_color, bd=0, highlightthickness=0)
            self.canvas.itemconfigure(self.toner_id, window=self.toner_prog)
        if isinstance(self.image_prog, ttk.Progressbar) and self.supplies['image_level'] == "N/A":
            self.image_prog.destroy()
            self.image_prog = tk.Frame(self.canvas, bg=self.bg_color, bd=0, highlightthickness=0)
            self.canvas.itemconfigure(self.image_id, window=self.image_prog)
        if isinstance(self.maint_prog, ttk.Progressbar) and self.supplies['maint_level'] == "N/A":
            self.maint_prog.destroy()
            self.maint_prog = tk.Frame(self.canvas, bg=self.bg_color, bd=0, highlightthickness=0)
            self.canvas.itemconfigure(self.maint_id, window=self.maint_prog)
        if isinstance(self.bottle_prog, ttk.Progressbar) and self.supplies['bottle_level'] == "N/A":
            self.bottle_prog.destroy()
            self.bottle_prog = tk.Frame(self.canvas, bg=self.bg_color, bd=0, highlightthickness=0)
            self.canvas.itemconfigure(self.bottle_id, window=self.bottle_prog)

    def destroy(self):
        popup_btn = [
            ("Yes", True, "#F09090", "#FFA0A0"),
            ("Cancel", False, None, None)
        ]
        dialog = PopupMessage(
            parent=self.canvas.winfo_toplevel(),
            title=f"Remove {self.printer_items['ip']}",
            message=f"Do you want to remove {self.printer_items['ip']}?",
            buttons=popup_btn
        )

        if dialog.result is True:
            self.canvas.destroy()

            if self.on_remove:
                self.on_remove(self)

class AddDialog(tk.Toplevel):
    def __init__(self, parent, title="Add Device", ips=None, new_printer_items=None, yes_btn="Add", no_btn="Cancel"):
        super().__init__(parent)
        self.parent = parent

        self.result = None
        self.ips = ips
        self.printer_items = new_printer_items
        self.yes_label = yes_btn
        self.no_label = no_btn

        self.title(title)
        self.configure(bg="#F0F0F0", padx=15, pady=15)
        self.geometry("300x300")
        self.minsize(300, 300)
        self.resizable(False, False)

        self.withdraw()

        # Form Frame
        form_frame = tk.Frame(self, bg="#F0F0F0")
        form_frame.pack(fill="x", expand=True, pady=(0, 15))

        form_frame.grid_columnconfigure(1, weight=1)

        # IP Labels and Entry
        ip_label = tk.Label(
            form_frame,
            text="IP Address : ",
            bg="#F0F0F0",
            fg="#000000",
            font=("Monospace", 10),
            justify="left",
            anchor="w"
        )
        ip_label.grid(row=0, column=0, sticky="w", padx=(0, 10), pady=6)

        self.entry_ip = tk.Entry(
            form_frame,
            bg="#F0F0F0",
            fg="#000000",
            relief="solid",
            highlightthickness=3,
            highlightbackground="#F0F0F0",
            bd=1
        )
        self.entry_ip.grid(row=0, column=1, sticky="ew", pady=6)

        # Name Label and Entry
        name_label = tk.Label(
            form_frame,
            text="Name       : ",
            bg="#F0F0F0",
            fg="#000000",
            font=("Monospace", 10),
            justify="left",
            anchor="w"
        )
        name_label.grid(row=1, column=0, sticky="w", padx=(0, 10), pady=6)

        self.entry_name = tk.Entry(
            form_frame,
            bg="#F0F0F0",
            fg="#000000",
            relief="solid",
            highlightthickness=3,
            highlightbackground="#F0F0F0",
            bd=1
        )
        self.entry_name.grid(row=1, column=1, sticky="ew", pady=6)
        # Location Label and Entry
        loc_label = tk.Label(
            form_frame,
            text="Location   : ",
            bg="#F0F0F0",
            fg="#000000",
            font=("Monospace", 10),
            justify="left",
            anchor="w"
        )
        loc_label.grid(row=2, column=0, sticky="w", padx=(0, 10), pady=6)

        self.entry_loc = tk.Entry(
            form_frame,
            bg="#F0F0F0",
            fg="#000000",
            relief="solid",
            highlightthickness=3,
            highlightbackground="#F0F0F0",
            bd=1
        )
        self.entry_loc.grid(row=2, column=1, sticky="ew", pady=6)
        # Protocol Label and Entry
        protocol_label = tk.Label(
            form_frame,
            text="Protocol   : ",
            bg="#F0F0F0",
            fg="#000000",
            font=("Monospace", 10),
            justify="left",
            anchor="w"
        )
        protocol_label.grid(row=3, column=0, sticky="w", padx=(0, 10), pady=6)

        self.entry_protocol = tk.Entry(
            form_frame,
            bg="#F0F0F0",
            fg="#000000",
            relief="solid",
            highlightthickness=3,
            highlightbackground="#F0F0F0",
            bd=1
        )
        self.entry_protocol.grid(row=3, column=1, sticky="ew", pady=6)
        # Endpoint Label and Entry
        endpoint_label = tk.Label(
            form_frame,
            text="Endpoint   : ",
            bg="#F0F0F0",
            fg="#000000",
            font=("Monospace", 10),
            justify="left",
            anchor="w"
        )
        endpoint_label.grid(row=4, column=0, sticky="w", padx=(0, 10), pady=6)

        self.entry_endpoint = tk.Entry(
            form_frame,
            bg="#F0F0F0",
            fg="#000000",
            relief="solid",
            highlightthickness=3,
            highlightbackground="#F0F0F0",
            bd=1
        )
        self.entry_endpoint.grid(row=4, column=1, sticky="ew", pady=6)

        # If configure, set items
        if self.printer_items is None:
            self.entry_protocol.insert(0, "http://")
            self.entry_endpoint.insert(0, "/webglue/rawcontent?c=Status&lang=en")
        else:
            self.entry_ip.insert(0, self.printer_items["ip"])
            self.entry_ip.config(state="readonly")
            self.entry_name.insert(0, self.printer_items["name"])
            self.entry_loc.insert(0, self.printer_items["location"])
            self.entry_protocol.insert(0, self.printer_items["protocol"])
            self.entry_endpoint.insert(0, self.printer_items["endpoint"])

        self.entry_ip.focus_set()

        btn_frame = tk.Frame(self, bg="#F0F0F0")
        btn_frame.pack(fill="x", expand=True)

        self.save_btn = tk.Button(
            btn_frame,
            text=self.yes_label,
            bg="#9090F0",
            fg="#000000",
            activebackground="#A0A0F0",
            activeforeground="#000000",
            relief="flat",
            padx=16,
            pady=6,
            command=self._on_save
        )
        self.save_btn.pack(side="right", padx=(5, 0))

        self.close_btn = tk.Button(
            btn_frame,
            text=self.no_label,
            bg="#F0F0F0",
            fg="#000000",
            activebackground="#FAFAFA",
            activeforeground="#000000",
            relief="flat",
            padx=16,
            pady=6,
            command=self._on_close
        )
        self.close_btn.pack(side="right", padx=(0, 5))

        # Modal setup
        self.transient(parent)
        parent.update_idletasks()
        self.update_idletasks()

        self._center_window(parent)
        self.deiconify()

        self.update()
        self.grab_set()
        self.wait_window()

    def _on_save(self):
        ip = self.entry_ip.get().strip()

        if self.yes_label == "Add" and ip in self.ips:
            PopupMessage(
                parent=self.parent.winfo_toplevel(),
                title=f"{ip} Exist",
                message=f"{ip} is already exists.",
                buttons=[("Ok", None, None, None)]
            )
            return

        if self.yes_label == "Save" and ip != self.printer_items["ip"]:
            if ip in self.ips:
                PopupMessage(
                    parent=self.parent.winfo_toplevel(),
                    title=f"{ip} Exist",
                    message=f"{ip} is already exists.",
                    buttons=[("Ok", None, None, None)]
                )
                return

        name = self.entry_name.get().strip()
        loc = self.entry_loc.get().strip()
        protocol = self.entry_protocol.get().strip()
        endpoint = self.entry_endpoint.get().strip()

        if self.yes_label == "Save":
            serial = self.printer_items["serial"]
        else:
            serial = "N/A"

        must_have = True

        if not ip:
            self.entry_ip.configure(highlightthickness=3, highlightbackground="#F0A0A0")
            must_have = False

        if not name:
            name = ip

        if not protocol:
            protocol = "http://"

        if not endpoint:
            endpoint = "/webglue/rawcontent?c=Status&lang=en"

        if self.yes_label == "Add":
            available = False
        else:
            available = self.printer_items["available"]

        if must_have:
            self.result = {
                "ip": ip,
                "name": name,
                "serial": serial,
                "location": loc,
                "protocol": protocol,
                "endpoint": endpoint,
                "available": available
            }
            self.destroy()

    def _on_close(self):
        if self.yes_label != "Save":
            self.result = None

        self.destroy()

    def _center_window(self, parent):
        self.update_idletasks()
        p_x = parent.winfo_rootx()
        p_y = parent.winfo_rooty()
        p_w = parent.winfo_width()
        p_h = parent.winfo_height()

        w = self.winfo_reqwidth()
        h = self.winfo_reqheight()

        x = p_x + (p_w // 2) - (w // 2)
        y = p_y + (p_h // 2) - (h // 2)
        self.geometry(f"{w}x{h}+{x}+{y}")

class TrayApp:
    def __init__(self):
        # Class Global Variables

        # Config Handler
        self.storage = ConfigHandler()
        self.first_init = True

        # Tkinker
        self.root = tk.Tk()
        self.hide_window()
        self.root.title(APP_NAME)
        self.root.geometry("450x400")
        self.root.minsize(450, 400)
        self.root.configure(bg="#F0F0F0")
        self.root.protocol("WM_DELETE_WINDOW", self.hide_window)

        # Hide
        self.root.withdraw()

        # Fonts
        self.root.option_add("*Font", ("Monospace", 10, "normal"))

        # List Container
        container = tk.Frame(self.root, bg="#F0F0F0")
        container.pack(fill="both", expand=True, padx=10, pady=10)

        self.canvas = tk.Canvas(container, bg="#F0F0F0", highlightthickness=0)
        self.scrollbar = tk.Scrollbar(container, orient="vertical", command=self._on_scrollbar_action)
        self.scrollbar.pack(side="right", fill="y")

        self.scroll_frame = tk.Frame(self.canvas, bg="#F0F0F0")

        # Store Window ID
        self.window_id = self.canvas.create_window((0, 0), window=self.scroll_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=self.scrollbar.set)

        self.canvas.pack(side="left", fill="both", expand=True)

        self.canvas.bind(
            "<Configure>",
            lambda e: self.canvas.itemconfig(self.window_id, width=e.width)
        )

        self.scroll_frame.bind(
            "<Configure>",
            lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        )

        # Mouse Scroll Bindings
        self.canvas.bind_all("<Button-4>", self._on_scroll)
        self.canvas.bind_all("<Button-5>", self._on_scroll)
        self.canvas.bind_all("<MouseWheel>", self._on_scroll)

        # If empty
        self.empty_label = tk.Label(
            self.canvas,
            text="No printers added yet.",
            bg="#F0F0F0",
            fg="#808080",
            font=("Monospace", 10, "bold italic")
        )
        self.empty_label_window = self.canvas.create_window(
            (0, 0),
            window=self.empty_label,
            anchor="center",
            state="normal"
        )
        self.canvas.bind("<Configure>", self._recenter_empty_label, add="+")
        # Row instance
        self.rows = []
        self.printer_ips = []

        # Buttons
        self.btn_frame = tk.Frame(self.root, bg="#F0F0F0")
        self.btn_frame.pack(side="right", fill="both", expand=True, padx=10, pady=10)
        tk.Button(self.btn_frame, text="Add Printer", relief="flat", command=self.add_button_click).pack(side="right", padx=5)
        tk.Button(self.btn_frame, text="Refresh", relief="flat", command=self.refresh_button_click).pack(side="right", padx=5)

        # Timer dropdown
        self.timer_values = [5, 10, 20, 30, 60, 90, 120]
        self.timer_frame = tk.Frame(self.root, bg="#F0F0F0")
        self.timer_frame.pack(side="left", fill="both", expand=True, padx=10, pady=10)
        self.timer_select = ttk.Combobox(
            self.timer_frame,
            values=self.timer_values,
            state="readonly",
            width=3
        )
        self.timer_select.pack(side="left", padx=5)
        if self.storage.get_timer() in self.timer_values:
            self.timer_select.set(self.storage.get_timer())
        else:
            self.timer_select.set(30)
        tk.Label(self.timer_frame, text="minutes timer", bg="#F0F0F0").pack(side="left")
        self.timer_select.bind("<<ComboboxSelected>>", self._on_select)

        # Tray events
        self.current_status = "default"
        self.warning_values = [0, 5, 10, 15, 20]
        self.setup_tray()

        if HAS_GTK:
            self.process_gtk_events()

        # Initial data from JSON
        self.init_from_json()

        # Start timer
        self.timer_id = None
        self._check_periodic()
        self._check_time_and_update()

        # Resurface
        self.root.update_idletasks()
        self.root.update()
        self.root.deiconify()
        self.root.grab_set()

    # Add printer
    def add_item(self, items, supplies):
        # Child List
        row = ListRowObject(
            parent_frame=self.scroll_frame,
            printer_items=items,
            supplies=supplies,
            on_config=self.config_button_click,
            on_web=self.web_button_click,
            on_remove=self.remove_item,
            warning_level=self.warning_values
        )
        self.rows.append(row)
        self.printer_ips.append(items["ip"])
        self._refresh_scroll_region()
        # Update tray status
        if not self.first_init:
            self.update_status()

    # Remove printer
    def remove_item(self, row_instance):
        if row_instance in self.rows:
            self.rows.remove(row_instance)
            self.printer_ips.remove(row_instance.printer_items["ip"])

            # Remove in JSON
            self.storage.remove_printer(row_instance.printer_items["ip"])
            self.storage.update_to_file()

        self._refresh_scroll_region()
        # Update tray status
        if not self.first_init:
            self.update_status()

    # Add button handler
    def add_button_click(self):
        dialog = AddDialog(parent=self.canvas.winfo_toplevel(), ips=self.printer_ips)
        if dialog.result is not None:
            res = dialog.result

            # Get Status
            status = PrinterStatusHandler(
                protocol=res["protocol"],
                ip=res["ip"],
                endpoint=res["endpoint"]
            )
            status.fetch_data()
            res["available"] = status.get_status()
            res["serial"] = status.get_serial()
            supplies = status.get_supplies()
            # Add in JSON
            self.storage.add_printer(
                ip=res["ip"],
                name=res["name"],
                serial=res["serial"],
                location=res["location"],
                protocol=res["protocol"],
                endpoint=res["endpoint"],
                available=res["available"],
                toner_lvl=supplies["toner_level"],
                toner_s=supplies["toner_status"],
                image_lvl=supplies["image_level"],
                image_s=supplies["image_status"],
                maint_lvl=supplies["maint_level"],
                maint_s=supplies["maint_status"],
                bottle_lvl=supplies["bottle_level"],
                bottle_s=supplies["bottle_status"]
            )
            self.storage.update_to_file()
            # Update to UI
            self.add_item(res, supplies)

    # Refresh button handler
    def refresh_button_click(self):
        for printer in self.rows:
            items = printer.printer_items
            status = PrinterStatusHandler(
                protocol=items["protocol"],
                ip=items["ip"],
                endpoint=items["endpoint"]
            )
            status.fetch_data()
            items["available"] = status.get_status()
            items["serial"] = status.get_serial()

            # If offline, use previous record data
            if status.get_status():
                supplies = status.get_supplies()
                # Set availability and supplies
                self.storage.set_printer(
                    ip=items["ip"],
                    available=items["available"],
                    serial=items["serial"],
                    toner_lvl=supplies["toner_level"],
                    toner_s=supplies["toner_status"],
                    image_lvl=supplies["image_level"],
                    image_s=supplies["image_status"],
                    maint_lvl=supplies["maint_level"],
                    maint_s=supplies["maint_status"],
                    bottle_lvl=supplies["bottle_level"],
                    bottle_s=supplies["bottle_status"]
                )
            else:
                supplies = self.storage.get_printers().get(items["ip"]).get("supplies")
                self.storage.set_printer(ip=items["ip"], available=items["available"], serial=items["serial"])

            self.storage.update_to_file()
            printer.update_inside(items, supplies)

    # Config button handler
    def config_button_click(self, printer_obj):
        printer_items = printer_obj.printer_items

        dialog = AddDialog(
            parent=self.canvas.winfo_toplevel(),
            title=f"Configure {printer_items['ip']}",
            ips=self.printer_ips,
            new_printer_items=printer_items,
            yes_btn="Save",
            no_btn="Close"
        )
        if dialog.result is not None:
            if printer_obj in self.rows:
                res = dialog.result
                idx = self.rows.index(printer_obj)
                status = PrinterStatusHandler(
                    protocol=res["protocol"],
                    ip=res["ip"],
                    endpoint=res["endpoint"]
                )
                status.fetch_data()
                res["serial"] = status.get_serial()
                res["available"] = status.get_status()
                self.rows[idx].update_inside(res, printer_obj.supplies)
                # Change in JSON
                self.storage.set_printer(
                    ip=res["ip"],
                    name=res["name"],
                    serial=res["serial"],
                    location=res["location"],
                    protocol=res["protocol"],
                    endpoint=res["endpoint"],
                    available=res["available"]
                )
                self.storage.update_to_file()

    # Web button handler
    def web_button_click(self, protocol, ip):
        webbrowser.open_new_tab(f"{protocol}{ip}")

    # Timer loop
    def _check_periodic(self):
        if not self.first_init:
            self.refresh_button_click()
        else:
            self.first_init = False
        self.timer_id = self.root.after(self.storage.get_timer() * 60 * 1000, self._check_periodic)

    # Daily timer
    def _check_time_and_update(self):
        now = datetime.now()
        current_time = now.strftime("%H:%M:%S")

        if current_time in self.storage.get_notify_times():
            self.update_status()

        self.root.after(1000, self._check_time_and_update)

    # Set printers
    def init_from_json(self):
        for printer, details in self.storage.get_printers().items():
            items = {
                "ip": printer,
                "name": details["name"],
                "serial": details["serial"],
                "location": details["location"],
                "protocol": details["protocol"],
                "endpoint": details["endpoint"],
                "available": details["available"]
            }
            # On Init Change Printer Status
            status = PrinterStatusHandler(
                protocol=items["protocol"],
                ip=items["ip"],
                endpoint=items["endpoint"]
            )
            status.fetch_data()
            # Set latest data
            items["available"] = status.get_status()
            items["serial"] = status.get_serial()

            # If offline, use previous record data
            if status.get_status():
                supplies = status.get_supplies()
                # Set availability and supplies
                self.storage.set_printer(
                    ip=items["ip"],
                    available=items["available"],
                    toner_lvl=supplies["toner_level"],
                    toner_s=supplies["toner_status"],
                    image_lvl=supplies["image_level"],
                    image_s=supplies["image_status"],
                    maint_lvl=supplies["maint_level"],
                    maint_s=supplies["maint_status"],
                    bottle_lvl=supplies["bottle_level"],
                    bottle_s=supplies["bottle_status"]
                )
            else:
                supplies = details["supplies"]
                self.storage.set_printer(ip=items["ip"], available=items["available"])
            # Update to file
            self.storage.update_to_file()
            # Update to list
            self.add_item(items, supplies)
        # Update tray status
        self.update_status()

    def _on_select(self, event):
        selected = self.timer_select.get()
        if int(selected) != self.storage.get_timer():
            if self.timer_id is not None:
                self.root.after_cancel(self.timer_id)
                self.timer_id = None
            self.storage.set_timer(selected)
            self.storage.update_to_file()
            self._check_periodic()

    # --- Window Functions ---
    def _check_empty_state(self):
        if not self.rows:
            self.canvas.itemconfigure(self.empty_label_window, state="normal")
        else:
            self.canvas.itemconfigure(self.empty_label_window, state="hidden")

    def _recenter_empty_label(self, event):
        self.canvas.coords(
            self.empty_label_window,
            event.width // 2,
            event.height // 2
        )

    def _refresh_scroll_region(self):
        self.scroll_frame.update_idletasks()
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        self._check_empty_state()

    def _on_scroll(self, event):
        content_height = self.scroll_frame.winfo_reqheight()
        canvas_height = self.canvas.winfo_height()

        if content_height > canvas_height:
            if event.num == 4:
                self.canvas.yview_scroll(-1, "units")
            elif event.num == 5:
                self.canvas.yview_scroll(1, "units")
            else:
                self.canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")

    def _on_scrollbar_action(self, action, *args):
        self.scroll_frame.update_idletasks()

        content_height = self.scroll_frame.winfo_reqheight()
        canvas_height = self.canvas.winfo_height()

        if content_height <= canvas_height:
            self.canvas.yview_moveto(0.0)
            return

        max_scroll = (content_height - canvas_height) / content_height

        if action == "moveto":
            fraction = float(args[0])
            clamped_fraction = max(0.0, min(fraction, max_scroll))
            self.canvas.yview_moveto(clamped_fraction)
        elif action == "scroll":
            number = int(args[0])
            unit = args[1]

            current_top = self.canvas.yview()[0]

            if unit == "units":
                step = 0.05 * number
            elif unit == "pages":
                step = 0.5 * number
            else:
                step = 0.0

            target_fraction = max(0.0, min(current_top + step, max_scroll))
            self.canvas.yview_moveto(target_fraction)

    def setup_tray(self):
        menu_items = pystray.Menu(
            item('Show App', self.show_window, default=True),
            item('Exit', self.quit_app)
        )

        self.icon = pystray.Icon(
            name=APP_NAME.lower().replace(" ", "_"),
            icon=status_icon(self.current_status),
            title=f"{APP_NAME} ({self.current_status.capitalize()})",
            menu=menu_items
        )

        self.icon.run_detached()

    def update_status(self):
        supplies_status = "default"
        min_values = 101
        for printer in self.storage.get_printers().keys():
            details = self.storage.get_printers()[printer]["supplies"]
            for supply, value in details.items():
                if isinstance(details[supply], (int, float)):
                    if value < min_values:
                        min_values = value
                    if value <= 20:
                        match supply:
                            case "toner_level":
                                message = "Printer Toner"
                            case "image_level":
                                message = "Imaging Unit"
                            case "maint_level":
                                message = "Maintenance Kit"
                            case "bottle_level":
                                message = "Waste Toner Bottle"
                            case _:
                                message = "None"

                        if value <= 5:
                            notify_urgent(f"{printer} - Low {message}", f"CRITICAL - Low {message} for printer '{printer}', {value}% left.")
                        else:
                            notify_normal(f"{printer} - Low {message}", f"Low {message} for printer '{printer}', {value}% left.")

        if min_values <= 5:
            supplies_status = "critical"
        elif min_values <= 20:
            supplies_status = "warning"
        elif min_values <= 100:
            supplies_status = "ok"

        self.set_status(supplies_status)

    def set_status(self, status_name):
        self.current_status = status_name
        new_icon = status_icon(status_name)
        # Set new icon status
        self.icon.icon = new_icon
        # Set new title
        self.icon.title = f"{APP_NAME} ({self.current_status.capitalize()})"

    def process_gtk_events(self):
        # GTK events handler
        try:
            while Gtk.events_pending():
                Gtk.main_iteration()
        except Exception:
            pass
        self.root.after(50, self.process_gtk_events)

    def show_window(self, icon=None, item=None):
        self.root.deiconify()
        self.root.lift()
        self.root.focus_force()

    def hide_window(self):
        self.root.withdraw()

    def quit_app(self, icon=None, item=None):
        self.icon.stop()
        self.root.destroy()
        sys.exit(0)

    def run(self):
        self.root.mainloop()
    # --- End Window Functions ---

if __name__ == "__main__":
    app = TrayApp()
    app.run()
