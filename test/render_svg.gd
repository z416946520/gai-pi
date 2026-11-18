extends SceneTree

## Renders an SVG to PNG so icon work can be checked without opening an editor.
##
##   SVG_IN=icon.svg SVG_OUT=.verify/icon.png SVG_SCALE=1 \
##     godot --headless --path . --script test/render_svg.gd


func _initialize() -> void:
	var source := OS.get_environment("SVG_IN")
	var target := OS.get_environment("SVG_OUT")
	var scale_env := OS.get_environment("SVG_SCALE")
	var scale := 1.0 if scale_env.is_empty() else scale_env.to_float()
	if source.is_empty() or target.is_empty():
		print("[svg] set SVG_IN and SVG_OUT")
		quit(1)
		return
	var source_text := FileAccess.get_file_as_string(source)
	if source_text.is_empty():
		print("[svg] cannot read ", source)
		quit(1)
		return
	var image := Image.new()
	var error := image.load_svg_from_string(source_text, scale)
	if error != OK:
		print("[svg] load failed: ", error)
		quit(1)
		return
	error = image.save_png(target)
	print("[svg] ", target, " ", image.get_width(), "x", image.get_height(), " error=", error)
	quit(0 if error == OK else 1)
