extends Button


func configure(title: String, status: String, reason: String, illustration: Texture2D, playable: bool) -> void:
	%StageTitle.text = title
	%StageStatus.text = status
	%StageReason.text = reason
	%StageReason.visible = not reason.is_empty()
	%Illustration.texture = illustration
	%Illustration.modulate = Color.WHITE if playable else Color(0.83, 0.83, 0.91)
	disabled = not playable
	accessibility_name = title
	accessibility_description = "%s %s" % [status, reason]
