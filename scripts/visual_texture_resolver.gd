class_name VisualTextureResolver
extends RefCounted

## Loads optional textures only when the file exists. Never fabricates missing refs.


static func try_load(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	if resource is Texture2D:
		return resource
	return null


static func first_existing(paths: Array[String]) -> Texture2D:
	for path in paths:
		var texture := try_load(path)
		if texture != null:
			return texture
	return null
