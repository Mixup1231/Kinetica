#version 450
#extension GL_EXT_debug_printf: enable

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;

layout(location = 0) out vec3 o_fragment_position;
layout(location = 1) out vec3 o_normal;
layout(location = 2) out vec2 o_uv;

struct Light {
    vec3 position;  
    vec3 color;
};

layout(binding = 0) readonly buffer ssbo{
    mat4 view_projection;
    mat4 model_matrices[100];
    Light lights[8];
    int texture_types;
};

void main() {
    mat4 model = model_matrices[gl_InstanceIndex];
    gl_Position = view_projection * model * vec4(a_position, 1.0);
    o_fragment_position = (model * vec4(a_position, 1.0)).xyz;
    o_normal = (model * vec4(a_normal, 1.0)).xyz;
    o_uv = a_uv;
}
