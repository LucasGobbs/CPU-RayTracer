package main

import rl "vendor:raylib"
import "core:c"

// Dark theme: near-black sidebar, amber accent.

editor_font: rl.Font

editor_text :: proc(x, y: c.int, text: cstring, size: c.int, color: rl.Color) {
	rl.DrawTextEx(editor_font, text, {f32(x), f32(y)}, f32(size), 1, color)
}

editor_text_width :: proc(text: cstring, size: c.int) -> c.int {
	return c.int(rl.MeasureTextEx(editor_font, text, f32(size), 1).x)
}

EDITOR_BG        :: rl.Color{18, 20, 27, 255}
PANEL_BG         :: rl.Color{26, 28, 38, 255}
PANEL_SECTION_BG :: rl.Color{38, 41, 54, 255}
HUD_BG           :: rl.Color{14, 15, 21, 235}
PANEL_BORDER     :: rl.Color{64, 70, 88, 255}
TEXT_PRIMARY     :: rl.Color{225, 228, 236, 255}
TEXT_MUTED       :: rl.Color{140, 146, 162, 255}
ACCENT           :: rl.Color{255, 170, 60, 255}
ACCENT_DIM       :: rl.Color{90, 70, 40, 255}
ACCENT_TEXT      :: rl.Color{24, 18, 8, 255}
CONTROL_BASE     :: rl.Color{44, 48, 62, 255}
CONTROL_HOVER    :: rl.Color{58, 63, 80, 255}
CONTROL_ACTIVE   :: rl.Color{68, 74, 94, 255}

editor_theme_init :: proc() {
	set :: rl.GuiSetStyle
	style :: proc(control: rl.GuiControl, prop: c.int, color: rl.Color) {
		set(control, prop, c.int(rl.ColorToInt(color)))
	}
	stylei :: proc(control: rl.GuiControl, prop: c.int, value: c.int) {
		set(control, prop, value)
	}

	editor_font = rl.LoadFontEx("vendor/fonts/JetBrainsMono-Regular.ttf", 28, nil, 0)
	rl.SetTextureFilter(editor_font.texture, .BILINEAR)
	rl.GuiSetFont(editor_font)

	P :: rl.GuiControlProperty
	D :: rl.GuiDefaultProperty

	style(.DEFAULT, c.int(P.TEXT_COLOR_NORMAL), TEXT_MUTED)
	style(.DEFAULT, c.int(P.BASE_COLOR_NORMAL), CONTROL_BASE)
	style(.DEFAULT, c.int(P.BORDER_COLOR_NORMAL), PANEL_BORDER)
	style(.DEFAULT, c.int(P.BASE_COLOR_FOCUSED), CONTROL_HOVER)
	style(.DEFAULT, c.int(P.BORDER_COLOR_FOCUSED), ACCENT_DIM)
	style(.DEFAULT, c.int(P.TEXT_COLOR_FOCUSED), TEXT_PRIMARY)
	style(.DEFAULT, c.int(P.BASE_COLOR_PRESSED), CONTROL_ACTIVE)
	style(.DEFAULT, c.int(P.BORDER_COLOR_PRESSED), ACCENT)
	style(.DEFAULT, c.int(P.TEXT_COLOR_PRESSED), TEXT_PRIMARY)
	style(.DEFAULT, c.int(P.BASE_COLOR_DISABLED), CONTROL_BASE)
	style(.DEFAULT, c.int(P.BORDER_COLOR_DISABLED), PANEL_BORDER)
	style(.DEFAULT, c.int(P.TEXT_COLOR_DISABLED), rl.Color{90, 94, 108, 255})
	stylei(.DEFAULT, c.int(P.BORDER_WIDTH), 1)
	stylei(.DEFAULT, c.int(D.TEXT_SIZE), 15)
	stylei(.DEFAULT, c.int(D.TEXT_SPACING), 1)
	style(.DEFAULT, c.int(D.BACKGROUND_COLOR), EDITOR_BG)
	style(.DEFAULT, c.int(D.LINE_COLOR), PANEL_BORDER)

	style(.SLIDER, c.int(P.BASE_COLOR_NORMAL), ACCENT)
	style(.SLIDER, c.int(P.BORDER_COLOR_NORMAL), ACCENT_DIM)
	style(.SLIDER, c.int(P.BASE_COLOR_FOCUSED), ACCENT)
	style(.SLIDER, c.int(P.BORDER_COLOR_FOCUSED), ACCENT)
	style(.SLIDER, c.int(P.BASE_COLOR_PRESSED), ACCENT)
	style(.SLIDER, c.int(P.BORDER_COLOR_PRESSED), ACCENT)
	stylei(.SLIDER, c.int(rl.GuiSliderProperty.SLIDER_PADDING), 2)

	style(.BUTTON, c.int(P.TEXT_COLOR_NORMAL), TEXT_PRIMARY)
	style(.BUTTON, c.int(P.BORDER_COLOR_NORMAL), PANEL_BORDER)
	style(.BUTTON, c.int(P.BORDER_COLOR_FOCUSED), ACCENT)
	style(.BUTTON, c.int(P.BASE_COLOR_PRESSED), ACCENT)
	style(.BUTTON, c.int(P.TEXT_COLOR_PRESSED), ACCENT_TEXT)

	style(.TOGGLE, c.int(P.TEXT_COLOR_NORMAL), TEXT_MUTED)
	style(.TOGGLE, c.int(P.BASE_COLOR_NORMAL), CONTROL_BASE)
	style(.TOGGLE, c.int(P.BORDER_COLOR_FOCUSED), ACCENT_DIM)
	style(.TOGGLE, c.int(P.TEXT_COLOR_FOCUSED), TEXT_PRIMARY)
	style(.TOGGLE, c.int(P.BASE_COLOR_PRESSED), ACCENT)
	style(.TOGGLE, c.int(P.BORDER_COLOR_PRESSED), ACCENT)
	style(.TOGGLE, c.int(P.TEXT_COLOR_PRESSED), ACCENT_TEXT)
	stylei(.TOGGLE, c.int(rl.GuiToggleProperty.GROUP_PADDING), 2)

	style(.DEFAULT, c.int(P.BASE_COLOR_NORMAL), PANEL_BG)
	style(.DEFAULT, c.int(P.BORDER_COLOR_NORMAL), PANEL_BG)
}
