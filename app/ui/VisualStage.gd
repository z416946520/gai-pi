class_name VisualStage
extends Control

## Agent-activity overlay: one shared shader/CustomDraw effect painting above the transcript.
##
## The effects are gai's (MIT, see CREDITS.md); each one reacts to the same event hooks the
## original app used, which is why [PiEvents] mirrors those signal shapes.

const CIRCUIT_BOARD_SCRIPT := preload("res://app/visuals/circuit_board/CircuitBoard.gd")

enum Type {
	NONE,
	RANDOM,
	# Same order as the groups in VisualEffectPreview.gd.
	JARVIS,
	TRANSFORMER,
	REASONING_TREE,
	TOOL_CONSTELLATION,
	CYBER_COMMAND_DECK,
	QUANTUM_CIRCUIT,
	CIRCUIT_BOARD,
	ORRERY,
	CONTEXT_MEMORY_RIVER,
	MATRIX_RAIN,
	PIANO_RHYTHM,
	NEURAL_AURORA,
	SEMANTIC_BLACK_HOLE,
	SOLAR_SYSTEM,
	DESKTOP_CAT,
	GEOMETRIC_GENESIS,
	INK_LANDSCAPE,
	PIXEL_CITY,
	KINTSUGI,
	HOLO_FOIL,
	STAINED_GLASS,
	TAI_CHI,
	FERROFLUID,
	SOAP_BUBBLES,
	FIREFLY_SYNC,
	LAVA_LAMP,
	MURMURATION,
	GO_BOARD,
	CLOCKWORK,
	ABACUS,
	FILTER_CAROUSEL,
	ELECTRONIC_CONTOURS,
	READING_LOUPE,
	PHOSPHOR_SCOPE,
	HEAT_MIRAGE,
	EINK_REFRESH,
	IMPOSSIBLE_ROOM,
	TEMPORAL_PRISM,
	TOPOLOGICAL_FOLD,
	INTERFACE_DELAMINATION,
	ZERO_GRAVITY,
	RIPPLE_SURFACE,
	TURING_BLOOM,
	THERMAL_TRACE,
	INK_FLUID,
	GLASS_RAIN,
	CHLADNI_PLATE,
	DATAMOSH,
	DARKROOM,
	PHYSARUM_NETWORK,
	FALLING_SAND,
	GAME_OF_LIFE,
	DOOM_FIRE,
	WARP_SPEED,
	PIPES_3D,
	FRACTAL_ZOOM,
	TESLA_LIGHTNING,
	DISINTEGRATE,
	SNAP_DISSOLVE,
}


static func create_effect(visual_type: Type) -> VisualEffect:
	if visual_type == Type.RANDOM:
		var visual_types: Array[int] = []
		for visual_name: String in Type:
			var candidate: int = Type[visual_name]
			if candidate != Type.NONE and candidate != Type.RANDOM:
				visual_types.append(candidate)
		visual_type = visual_types.pick_random() as Type
		Log.info("VisualControl: random effect:[{}]", Type.keys()[visual_type])
	match visual_type:
		Type.JARVIS:
			return JarvisControl.new()
		Type.TRANSFORMER:
			return TransformerController.new()
		Type.REASONING_TREE:
			return ReasoningTree.new()
		Type.TOOL_CONSTELLATION:
			return ToolConstellation.new()
		Type.CYBER_COMMAND_DECK:
			return CyberCommandDeck.new()
		Type.QUANTUM_CIRCUIT:
			return QuantumCircuit.new()
		Type.CIRCUIT_BOARD:
			return CIRCUIT_BOARD_SCRIPT.new() as VisualEffect as VisualEffect
		Type.ORRERY:
			return Orrery.new()
		Type.CONTEXT_MEMORY_RIVER:
			return ContextMemoryRiver.new()
		Type.MATRIX_RAIN:
			return MatrixRain.new()
		Type.PIANO_RHYTHM:
			return PianoRhythm.new()
		Type.NEURAL_AURORA:
			return NeuralAurora.new()
		Type.SEMANTIC_BLACK_HOLE:
			return SemanticBlackHole.new()
		Type.SOLAR_SYSTEM:
			return SolarSystem.new()
		Type.DESKTOP_CAT:
			return DesktopCat.new()
		Type.GEOMETRIC_GENESIS:
			return GeometricGenesis.new()
		Type.INK_LANDSCAPE:
			return InkLandscape.new()
		Type.PIXEL_CITY:
			return PixelCity.new()
		Type.KINTSUGI:
			return Kintsugi.new()
		Type.HOLO_FOIL:
			return HoloFoil.new()
		Type.STAINED_GLASS:
			return StainedGlass.new()
		Type.TAI_CHI:
			return TaiChi.new()
		Type.FERROFLUID:
			return Ferrofluid.new()
		Type.SOAP_BUBBLES:
			return SoapBubbles.new()
		Type.FIREFLY_SYNC:
			return FireflySync.new()
		Type.LAVA_LAMP:
			return LavaLamp.new()
		Type.MURMURATION:
			return Murmuration.new()
		Type.GO_BOARD:
			return GoBoard.new()
		Type.CLOCKWORK:
			return Clockwork.new()
		Type.ABACUS:
			return Abacus.new()
		Type.FILTER_CAROUSEL:
			return FilterCarousel.new()
		Type.ELECTRONIC_CONTOURS:
			return ElectronicContours.new()
		Type.READING_LOUPE:
			return ReadingLoupe.new()
		Type.PHOSPHOR_SCOPE:
			return PhosphorScope.new()
		Type.HEAT_MIRAGE:
			return HeatMirage.new()
		Type.EINK_REFRESH:
			return EInkRefresh.new()
		Type.IMPOSSIBLE_ROOM:
			return ImpossibleRoom.new()
		Type.TEMPORAL_PRISM:
			return TemporalPrism.new()
		Type.TOPOLOGICAL_FOLD:
			return TopologicalFold.new()
		Type.INTERFACE_DELAMINATION:
			return InterfaceDelamination.new()
		Type.ZERO_GRAVITY:
			return ZeroGravity.new()
		Type.RIPPLE_SURFACE:
			return RippleSurface.new()
		Type.TURING_BLOOM:
			return TuringBloom.new()
		Type.THERMAL_TRACE:
			return ThermalTrace.new()
		Type.INK_FLUID:
			return InkFluid.new()
		Type.GLASS_RAIN:
			return GlassRain.new()
		Type.CHLADNI_PLATE:
			return ChladniPlate.new()
		Type.DATAMOSH:
			return Datamosh.new()
		Type.DARKROOM:
			return Darkroom.new()
		Type.PHYSARUM_NETWORK:
			return PhysarumNetwork.new()
		Type.FALLING_SAND:
			return FallingSand.new()
		Type.GAME_OF_LIFE:
			return GameOfLife.new()
		Type.DOOM_FIRE:
			return DoomFire.new()
		Type.WARP_SPEED:
			return WarpSpeed.new()
		Type.PIPES_3D:
			return Pipes3D.new()
		Type.FRACTAL_ZOOM:
			return FractalZoom.new()
		Type.TESLA_LIGHTNING:
			return TeslaLightning.new()
		Type.DISINTEGRATE:
			return Disintegrate.new()
		Type.SNAP_DISSOLVE:
			return SnapDissolve.new()
	return null


var current_effect: VisualEffect = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	PiEvents.events.agent_start.connect(on_agent_start)
	PiEvents.events.agent_end.connect(on_agent_end)
	PiEvents.events.turn_start.connect(on_turn_start)
	PiEvents.events.turn_end.connect(on_turn_end)
	PiEvents.events.message_update.connect(on_message_update)
	PiEvents.events.message_complete.connect(on_message_complete)
	PiEvents.events.tool_execution_start.connect(on_tool_execution_start)
	PiEvents.events.tool_execution_end.connect(on_tool_execution_end)
	PiEvents.events.chat_entry_add.connect(on_chat_entry_add)
	pass


## Effect type names in enum order, for the toolbar picker.
static func type_names() -> PackedStringArray:
	var names := PackedStringArray()
	for key: String in Type:
		names.append(key)
	return names


static func localized_name(type_index: int) -> String:
	var names := type_names()
	if type_index < 0 or type_index >= names.size():
		return "None"
	var key := "agent.toolbar.visual_" + names[type_index].to_lower()
	var translated := I18n.t(key)
	return translated if translated != key else names[type_index].capitalize()


func prepare_effect() -> VisualEffect:
	if current_effect != null:
		if current_effect.visible:
			return current_effect
		current_effect.queue_free()
		current_effect = null
	var visual_type := AppSetting.get_int(AppSetting.KEY_VISUAL, Type.NONE) as Type
	if visual_type == Type.NONE:
		return null
	var effect := create_effect(visual_type)
	if effect == null:
		effect = create_effect(Type.RANDOM)
	if effect == null:
		return null
	current_effect = effect
	add_child(effect)
	effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return current_effect


func on_agent_start(session_id: int) -> void:
	var effect := prepare_effect()
	if effect == null or effect.visible:
		return
	effect.on_agent_start(session_id)
	effect.set_visual_visible(true, true)


func on_agent_end(session_id: int, error_message: String) -> void:
	if RuntimeManager.is_active():
		return
	var effect := current_effect
	if is_instance_valid(effect):
		await effect.on_agent_end(session_id, error_message)
	if RuntimeManager.is_active():
		return
	if is_instance_valid(effect):
		effect.set_visual_visible(false, true)


func on_turn_start(session_id: int) -> void:
	var effect := get_running_effect(session_id)
	if effect != null:
		effect.on_turn_start(session_id)


func on_turn_end(session_id: int) -> void:
	var effect := get_running_effect(session_id)
	if effect != null:
		effect.on_turn_end(session_id)


func on_message_update(session_id: int, chunk: String, stream_kind: String) -> void:
	var effect := get_running_effect(session_id)
	if effect != null:
		effect.on_message_update(session_id, chunk, stream_kind)


func on_message_complete(session_id: int, usage: OpenAiUsage) -> void:
	var effect := get_running_effect(session_id)
	if effect != null:
		effect.on_message_complete(session_id, usage)


func on_tool_execution_start(session_id: int, tool_call_id: String, tool_name: String, args: Dictionary) -> void:
	var effect := get_running_effect(session_id)
	if effect == null:
		return
	var typed_args: Dictionary[String, Variant] = {}
	typed_args.assign(args)
	effect.on_tool_execution_start(session_id, tool_call_id, tool_name, typed_args)


func on_tool_execution_end(session_id: int, tool_call_id: String, tool_name: String, agent_tool_result: AgentToolResult) -> void:
	var effect := get_running_effect(session_id)
	if effect != null:
		effect.on_tool_execution_end(session_id, tool_call_id, tool_name, agent_tool_result)


func on_chat_entry_add(session_id: int, entry: ChatEntry) -> void:
	var effect := get_running_effect(session_id)
	if effect != null:
		effect.on_chat_entry_add(session_id, entry)


func get_running_effect(session_id: int) -> VisualEffect:
	if not RuntimeManager.is_running(session_id):
		return null
	var effect := current_effect
	return effect if effect != null and effect.visible else null
