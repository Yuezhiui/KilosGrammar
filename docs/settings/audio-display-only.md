# Settings: Audio & Display only

The Main Menu **Settings** entry remains active. Its entire screen is now
the single editor-authored `SettingsPage` at
`ui/secondary/settings.tscn`; the first screenshot's old Controls and
Camera documentation was removed because the educational game uses
real physical body movement, not an old keyboard-only preview.

Removed from the active scene:
- `SettingsCard/SidebarPanel` including `SidebarSettingsTab`,
  `SidebarControlsTab`, and `SidebarCameraTab`
- `SettingsCard/CardPadding/BoardLayout/ContentStack/PageHost/PageScroll/ControlsPage`
- `SettingsCard/CardPadding/BoardLayout/ContentStack/PageHost/PageScroll/CameraPage`
- unused serialized tab texture/style resources; old demo camera wording
- obsolete decorative `MainStage/TextureRect` cat image that previously
  overlapped the Fullscreen row. Its now-orphaned
  `Components/Settings/Secondary/qwqwqw.png` and `.import` were deleted
  after a full reference scan.

All active rows are individually editable Godot scene nodes:
Master Volume, Music, Effects, Mute All Audio, and Fullscreen, plus a
separate Header and BackButton. The main CardPadding now uses 72-pixel
left/right editor offsets instead of reserving 239 pixels for the
removed sidebar, so Audio & Display occupies the center of the board.
The Classroom artwork, Settings title, audio icons, board art and Back
button remain. Runtime can still scale the entire board responsively
but never creates another Controls or Camera page.

Volume sliders continue controlling their actual local AudioServer buses;
the Mute toggle controls Master, and Fullscreen toggles the OS display
mode. The corresponding preferences persist in
`user://kilos_settings.cfg`. Open the scene in Godot 2D to drag/resize
the controls directly. All older Settings screenshots/tests now target
the single Audio & Display page; the legacy scene generator is disabled
to avoid overwriting editor-authored UI.
