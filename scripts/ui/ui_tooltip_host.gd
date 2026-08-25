class_name UITooltipHost
extends PanelContainer
## Hover host that renders a styled [UITooltip] via Godot's custom tooltip hook.

## Optional factory: () -> Control. Prefer this for live content.
var tip_factory: Callable = Callable()


func _make_custom_tooltip(for_text: String) -> Object:
	if tip_factory.is_valid():
		var built: Variant = tip_factory.call()
		if built is Control:
			return built as Control
	if for_text.strip_edges().is_empty():
		return null
	return UITooltip.create(for_text)
