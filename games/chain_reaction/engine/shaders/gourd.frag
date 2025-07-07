#version 450
#extension GL_EXT_debug_printf: enable

layout(location = 0) in vec3 i_fragment_position;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;

layout(location = 0) out vec4 o_color;

struct Light {
    vec3 position;  
    vec3 color;
};

struct Shader_Data {
    mat4 view_projection;
    mat4 model_matrices[100];
    Light lights[8];
    int texture_types;
};

layout(binding = 0) readonly buffer ssbo{
    Shader_Data shader_data;
};

layout(binding = 1) uniform sampler2D s_albedo;
layout(binding = 2) uniform sampler2D s_emissive;

void main() {
    vec3 normal = normalize(a_normal);
    float ambient_strength = 0.1;
    vec3 ambient = ambient_strength * vec3(1.0, 1.0, 1.0);

    vec3 light_direction = normalize(vec3(0.0, -2.0, 0.0) - i_fragment_position);
    float diffuse_strength = max(dot(normal, light_direction), 0.0);
    vec3 diffuse = diffuse_strength * vec3(1.0, 1.0, 1.0);    

    o_color = vec4((ambient + diffuse) * vec3(1.0, 1.0, 1.0), 1.0);
}
