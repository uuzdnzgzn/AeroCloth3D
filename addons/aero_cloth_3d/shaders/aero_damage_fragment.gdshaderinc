// Shared by undeformed meshes and the CPU-authoritative GPU proxy deformation.
// UV2 selects only the damage atlas; source PBR maps continue to use source UV0.
uniform sampler2D base_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_metallic_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_base_albedo = false;
uniform bool use_base_normal = false;
uniform bool use_base_roughness_texture = false;
uniform bool use_base_metallic_texture = false;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D mask_texture : hint_default_transparent, filter_linear, repeat_disable;
uniform sampler2D damage_normal : hint_normal, filter_linear, repeat_disable;
// Runtime opt-in avoids CPU normal-map regeneration during simultaneous hits.
// RF relief remains CPU-authoritative; only its surface shading is derived here.
uniform sampler2D damage_height : hint_default_black, filter_linear, repeat_disable;
uniform bool use_damage_height = false;
uniform float damage_height_scale : hint_range(0.0, 4.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.39, 0.074, 0.050, 1.0);
uniform bool use_damage_uv2 = false;
uniform float cut_strength : hint_range(0.0, 1.0) = 1.0;
uniform float normal_strength : hint_range(0.0, 4.0) = 1.0;
uniform float wear_strength : hint_range(0.0, 1.0) = 1.0;
uniform float burn_strength : hint_range(0.0, 1.0) = 1.0;
uniform float blood_strength : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
// Optional per-zone material stages. A = cut/normal/wear/burn; B.x = blood.
// Count zero preserves the single-stage material API. With zones enabled,
// unmatched texels receive zero damage; the first containing UV rectangle wins.
uniform int damage_region_count = 0;
uniform vec4 damage_region_rects[16];
uniform vec4 damage_region_strength_a[16];
uniform vec4 damage_region_strength_b[16];

vec3 aero_rnm(vec3 base, vec3 detail) {
	vec3 t = base + vec3(0.0, 0.0, 1.0);
	vec3 u = detail * vec3(-1.0, -1.0, 1.0);
	return normalize(t * dot(t, u) / max(t.z, 0.00001) - u);
}

vec3 aero_height_normal(vec2 uv) {
	ivec2 dimensions = max(textureSize(damage_height, 0), ivec2(1));
	ivec2 cell = clamp(ivec2(floor(uv * vec2(dimensions))), ivec2(0), dimensions - ivec2(1));
	float left_height = texelFetch(damage_height, clamp(cell - ivec2(1, 0), ivec2(0), dimensions - ivec2(1)), 0).r;
	float right_height = texelFetch(damage_height, clamp(cell + ivec2(1, 0), ivec2(0), dimensions - ivec2(1)), 0).r;
	float top_height = texelFetch(damage_height, clamp(cell - ivec2(0, 1), ivec2(0), dimensions - ivec2(1)), 0).r;
	float bottom_height = texelFetch(damage_height, clamp(cell + ivec2(0, 1), ivec2(0), dimensions - ivec2(1)), 0).r;
	vec2 slope = vec2(right_height - left_height, bottom_height - top_height) * vec2(dimensions) * 0.5 * damage_height_scale;
	return normalize(vec3(-slope, 1.0));
}

void fragment() {
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	vec2 damage_uv = use_damage_uv2 ? UV2 : UV;
	vec4 damage = texture(mask_texture, damage_uv);
	vec4 region_strength_a = vec4(1.0);
	vec4 region_strength_b = vec4(1.0);
	int region_count = clamp(damage_region_count, 0, 16);
	if (region_count > 0) {
		region_strength_a = vec4(0.0);
		region_strength_b = vec4(0.0);
		for (int region_index = 0; region_index < 16; region_index++) {
			if (region_index >= region_count) { break; }
			vec4 rect = damage_region_rects[region_index];
			if (rect.z > 0.0 && rect.w > 0.0 && all(greaterThanEqual(damage_uv, rect.xy)) && all(lessThanEqual(damage_uv, rect.xy + rect.zw))) {
				region_strength_a = max(damage_region_strength_a[region_index], vec4(0.0));
				region_strength_b = max(damage_region_strength_b[region_index], vec4(0.0));
				break;
			}
		}
	}
	float wear = clamp(damage.g * wear_strength * region_strength_a.z, 0.0, 1.0);
	float burn = clamp(damage.b * burn_strength * region_strength_a.w, 0.0, 1.0);
	float blood = clamp(damage.a * blood_strength * region_strength_b.x, 0.0, 1.0);
	vec4 sampled_albedo = use_base_albedo ? texture(base_albedo, UV) : vec4(1.0);
	vec3 albedo = sampled_albedo.rgb * tint.rgb;
	albedo = mix(albedo, albedo * 0.55 + vec3(0.32, 0.31, 0.28), wear);
	albedo = mix(albedo, vec3(0.035, 0.022, 0.014), burn);
	albedo = mix(albedo, vec3(0.19, 0.008, 0.012), blood);
	ALBEDO = albedo;
	float roughness = base_roughness * (use_base_roughness_texture ? texture(base_roughness_texture, UV).r : 1.0);
	float metallic = base_metallic * (use_base_metallic_texture ? texture(base_metallic_texture, UV).r : 1.0);
	ROUGHNESS = clamp(roughness + wear * 0.15 + burn * 0.1 - blood * 0.32, 0.02, 1.0);
	METALLIC = clamp(metallic * (1.0 - burn * 0.6) * (1.0 - blood * 0.8), 0.0, 1.0);
	vec3 n1 = use_base_normal ? normalize(texture(base_normal, UV).xyz * 2.0 - 1.0) : vec3(0.0, 0.0, 1.0);
	vec3 n2 = use_damage_height ? aero_height_normal(damage_uv) : texture(damage_normal, damage_uv).xyz * 2.0 - 1.0;
	n2 = normalize(vec3(n2.xy * normal_strength * region_strength_a.y, max(n2.z, 0.0001)));
	// An independently rotated UV2 island has a different tangent frame. Reorient
	// its detail normal into UV0's frame before RNM preserves the source normal.
	if (use_damage_uv2) {
		vec2 duvdx = dFdx(UV2);
		vec2 duvdy = dFdy(UV2);
		float determinant = duvdx.x * duvdy.y - duvdx.y * duvdy.x;
		if (abs(determinant) > 0.00000001 && length(TANGENT) > 0.0001 && length(BINORMAL) > 0.0001) {
			vec3 dpdx = dFdx(VERTEX);
			vec3 dpdy = dFdy(VERTEX);
			vec3 detail_tangent = normalize((dpdx * duvdy.y - dpdy * duvdx.y) / determinant);
			vec3 detail_bitangent = normalize((dpdy * duvdx.x - dpdx * duvdy.x) / determinant);
			vec3 detail_view = normalize(detail_tangent * n2.x + detail_bitangent * n2.y + NORMAL * n2.z);
			n2 = normalize(vec3(dot(detail_view, normalize(TANGENT)), dot(detail_view, normalize(BINORMAL)), dot(detail_view, normalize(NORMAL))));
		}
	}
	NORMAL_MAP = aero_rnm(n1, n2) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ALPHA = sampled_albedo.a * tint.a * (1.0 - clamp(damage.r * cut_strength * region_strength_a.x, 0.0, 1.0));
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
