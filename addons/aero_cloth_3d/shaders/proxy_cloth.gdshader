shader_type spatial;
render_mode cull_disabled;

// 99 CPU-authoritative points. XYZ = cloth-local position; A = painted mobility.
uniform sampler2D proxy_data : filter_nearest, repeat_disable;
uniform bool show_weights = false;
varying float mobility;

void vertex() {
	vec2 cell = UV * vec2(8.0, 10.0);
	ivec2 base = min(ivec2(floor(cell)), ivec2(7, 9));
	vec2 t = cell - vec2(base);
	vec4 a = texelFetch(proxy_data, base, 0);
	vec4 b = texelFetch(proxy_data, base + ivec2(0,1), 0);
	vec4 c = texelFetch(proxy_data, base + ivec2(1,0), 0);
	vec4 d = texelFetch(proxy_data, base + ivec2(1,1), 0);
	vec4 p;
	vec3 n;
	if (t.x + t.y <= 1.0) {
		p = a + t.x * (c-a) + t.y * (b-a);
		n = cross(b.xyz-a.xyz, c.xyz-a.xyz);
	} else {
		p = d + (1.0-t.x) * (b-d) + (1.0-t.y) * (c-d);
		n = cross(b.xyz-c.xyz, d.xyz-c.xyz);
	}
	VERTEX = p.xyz;
	NORMAL = length(n) > 0.000001 ? normalize(n) : vec3(0.0,0.0,1.0);
	mobility = p.w;
}

void fragment() {
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	ALBEDO = show_weights ? (mobility < 0.01 ? vec3(1.0,0.51,0.14) : (mobility < 0.99 ? vec3(0.11,0.75,0.64) : vec3(0.17,0.25,0.37))) : vec3(0.39,0.074,0.050);
	ROUGHNESS = 0.95;
}
