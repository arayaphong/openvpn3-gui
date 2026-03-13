project('openvpn-gui', 'vala', 'c')

gtk_dep = dependency('gtk+-3.0')
glib_dep = dependency('glib-2.0')
gio_dep = dependency('gio-2.0')
posix_dep = meson.get_compiler('vala').find_library('posix')

c_args = [
  '-Wno-unused-but-set-variable',
  '-Wno-unused-function',
  '-Wno-unused-variable',
  '-Wno-discarded-qualifiers',
  '-w',
]

vala_args = [
  '--disable-warnings',
]

executable(
  'openvpn-gui',
  'src/openvpn-gui.vala',
  dependencies: [gtk_dep, glib_dep, gio_dep, posix_dep],
  c_args: c_args,
  vala_args: vala_args,
  install: true,
  install_dir: 'bin'
)
