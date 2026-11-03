shader_type canvas_item;
render_mode unshaded;

// One shared twelve-segment strip; each instance supplies its own bend.
void vertex() {
	VERTEX.x += sin(UV.y * PI) * INSTANCE_CUSTOM.x;
}
