shader_type spatial;
render_mode cull_disabled;
uniform sampler2D proxy_data : filter_nearest, repeat_disable;
uniform sampler2D proxy_rest_data : filter_nearest, repeat_disable;

void vertex() {
	vec3 a = texelFetch(proxy_data,ivec2(int(CUSTOM0.x),0),0).xyz;
	vec3 b = texelFetch(proxy_data,ivec2(int(CUSTOM0.y),0),0).xyz;
	vec3 c = texelFetch(proxy_data,ivec2(int(CUSTOM0.z),0),0).xyz;
	vec3 cross_value = cross(b-a,c-a);
	vec3 n = length(cross_value)>0.000001 ? normalize(cross_value) : vec3(0,0,1);
	vec3 ra = texelFetch(proxy_rest_data,ivec2(int(CUSTOM0.x),0),0).xyz;
	vec3 rb = texelFetch(proxy_rest_data,ivec2(int(CUSTOM0.y),0),0).xyz;
	vec3 rc = texelFetch(proxy_rest_data,ivec2(int(CUSTOM0.z),0),0).xyz;
	vec3 rx = normalize(rb-ra);
	vec3 rn = normalize(cross(rb-ra,rc-ra));
	vec3 ry = cross(rn,rx);
	vec3 x = length(b-a)>0.000001 ? normalize(b-a) : rx;
	vec3 y = cross(n,x);
	vec3 original_tangent = TANGENT;
	vec3 original_binormal = BINORMAL;
	VERTEX = a*CUSTOM1.x+b*CUSTOM1.y+c*CUSTOM1.z+n*CUSTOM0.w;
	NORMAL = n;
	TANGENT = length(original_tangent)>0.000001 ? normalize(x*dot(original_tangent,rx)+y*dot(original_tangent,ry)+n*dot(original_tangent,rn)) : x;
	BINORMAL = length(original_binormal)>0.000001 ? normalize(x*dot(original_binormal,rx)+y*dot(original_binormal,ry)+n*dot(original_binormal,rn)) : cross(n,TANGENT);
}

#include "res://addons/aero_cloth_3d/shaders/aero_damage_fragment.gdshaderinc"
