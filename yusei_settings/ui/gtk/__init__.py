"""
yusei_settings.ui.gtk
~~~~~~~~~~~~~~~~~~~~~
Native GTK4 and Libadwaita desktop interface for Linux/Hyprland.
"""

from .window import launch_gtk_app, is_gtk_available

__all__ = ["launch_gtk_app", "is_gtk_available"]
