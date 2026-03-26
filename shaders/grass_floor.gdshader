shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D grass_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec2 uv_scale = vec2(3.0, 3.0);

void fragment() {
	vec2 tiled_uv = UV * uv_scale;
	vec4 color = texture(grass_texture, tiled_uv);
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ROUGHNESS = 1.0;
}
