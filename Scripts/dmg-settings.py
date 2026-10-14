"""Finder drag-to-install layout, consumed by dmgbuild (no UI automation)."""

files = [defines["app"]]
symlinks = {"Applications": defines.get("applications", "/Applications")}
background = defines["background"]
format = "UDZO"
filesystem = "HFS+"
window_rect = ((200, 200), (680, 400))
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_sidebar = False
show_pathbar = False
show_tab_view = False
arrange_by = None
icon_size = 88
text_size = 13
label_pos = "bottom"
icon_locations = {"English Compass.app": (180, 200), "Applications": (500, 200)}
