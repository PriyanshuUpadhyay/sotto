# dmgbuild settings for the Sotto installer window (scripts/make-dmg.sh).
#
# The layout is written straight into the volume's .DS_Store instead of being
# recorded through Finder scripting: on macOS 26 Finder persists the build
# Mac's tab bar into the window state and, when a hidden item is laid out
# above the window top, shifts every icon down to fit it. Coordinates are
# Finder icon centres in the 640x400 content area, top-left origin, and must
# match scripts/dmg/make-background.swift.
#
# Inputs arrive as -D defines from make-dmg.sh. A missing one raises KeyError
# on purpose: the build must stop rather than package a half-configured image.
import os

app = defines["app"]
background = defines["background"]
icon = defines["icon"]

format = "UDZO"
compression_level = 9
filesystem = "HFS+"

files = [app]
symlinks = {"Applications": "/Applications"}

# dmgbuild copies the art to the volume root as .background<ext>, and builds a
# multi-resolution TIFF when a <name>@2x<ext> sibling exists next to it.
_bg_root, _bg_ext = os.path.splitext(background)
_bg_in_image = (
    ".background.tiff" if os.path.exists(f"{_bg_root}@2x{_bg_ext}") else f".background{_bg_ext}"
)

# The frame includes the 32 pt macOS 26 title bar, so the art fills the content.
window_rect = ((200, 120), (640, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 12
label_pos = "bottom"
arrange_by = None

# Dot-files stay hidden for a default Finder and the invisible flag covers the
# rest. A Finder set to show hidden files lists them anyway, so park them
# outside the window: Finder's default slot for an unplaced item sits above
# the window top, and fitting it there is what shifts every icon down.
hide = [_bg_in_image, ".VolumeIcon.icns"]
icon_locations = {
    os.path.basename(app): (165, 205),
    "Applications": (475, 205),
    _bg_in_image: (1200, 205),
    ".VolumeIcon.icns": (1400, 205),
}
