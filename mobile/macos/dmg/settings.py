# The Mac install window's layout, read by dmgbuild through make-dmg.sh. dmgbuild writes the window's .DS_Store
# itself, with no Finder. The background's spots for the two icons match brand/make-icons.mjs.
import os.path

app = defines['app']  # noqa: F821 (dmgbuild gives it)
background = defines['background']  # noqa: F821

format = 'UDZO'
files = [app]
symlinks = {'Applications': '/Applications'}
icon = os.path.join(app, 'Contents', 'Resources', 'AppIcon.icns')

# Finder's window size counts its title bar: 28 more than the 660 by 400 background, so all of it shows.
window_rect = ((200, 120), (660, 428))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 128
icon_locations = {
    os.path.basename(app): (170, 188),
    'Applications': (490, 188),
}
