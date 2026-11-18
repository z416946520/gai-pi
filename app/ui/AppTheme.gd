class_name AppTheme
extends Object

## Semantic shell colors that follow [ThemeColor.current_theme].
##
## The shell's panels, bubbles, and dialogs are built once with these values, so switching
## themes rebuilds the interface instead of trying to repaint every style in place. Effects
## already adapt through gai's [VisualColor].

static func is_dark() -> bool:
	return ThemeColor.is_dark_theme()


static func background() -> Color:
	return Colors.DARK_BACKGROUND if is_dark() else Colors.LIGHT_BACKGROUND


static func deep_surface() -> Color:
	return Colors.DARK_DEEP_SURFACE if is_dark() else Colors.LIGHT_DEEP_SURFACE


static func chrome_surface() -> Color:
	return Colors.DARK_CHROME_SURFACE if is_dark() else Colors.LIGHT_CHROME_SURFACE


static func control_surface() -> Color:
	return Colors.DARK_CONTROL_SURFACE if is_dark() else Colors.LIGHT_CONTROL_SURFACE


static func container_surface() -> Color:
	return Colors.DARK_SURFACE_CONTAINER if is_dark() else Colors.LIGHT_SURFACE_CONTAINER


static func container_high() -> Color:
	return Colors.DARK_SURFACE_CONTAINER_HIGH if is_dark() else Colors.LIGHT_SURFACE_CONTAINER_HIGH


static func outline() -> Color:
	return Colors.DARK_OUTLINE_VARIANT if is_dark() else Colors.LIGHT_OUTLINE_VARIANT


## Text drawn on top of the accent color; the accent stays bright in both themes.
static func on_accent() -> Color:
	return Colors.DARK_BACKGROUND


## Neon strokes and status hues were authored for a dark canvas; on light they need weight.
static func ink(color: Color) -> Color:
	return color if is_dark() else color.darkened(0.42)
