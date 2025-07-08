#version 450

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;

layout(location = 0) out vec3 o_fragment_position;
layout(location = 1) out vec3 o_normal;
layout(location = 2) out vec2 o_uv;

struct Point_Light {
    vec4  position;  
    vec4  color;
};

layout(binding = 0) readonly buffer cold_ssbo{
    mat4 view_projection;
    Point_Light point_lights[8];
    vec4 camera_position;
    vec4 ambient_color;
    float ambient_strength;
    uint point_light_count;
};

layout(binding = 1) readonly buffer hot_ssbo{
    mat4 model_matrices[100];
    uint texture_types;
};

void main() {
    mat4 model = model_matrices[gl_InstanceIndex];
    gl_Position = view_projection * model * vec4(a_position, 1.0);
    o_fragment_position = (model * vec4(a_position, 1.0)).xyz;
    // expensive so precompute on cpu
    mat3 normal_matrix = transpose(inverse(mat3(model)));
    o_normal = normal_matrix * a_normal;
    o_uv = a_uv;
}
