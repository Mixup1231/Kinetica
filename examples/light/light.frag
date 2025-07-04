#version 450

layout(location = 0) out vec4 outColor;

layout(location = 0) in vec3 inColor;
layout(location = 1) in vec3 inFragPos;
layout(location = 2) in vec3 inNormal;

layout(binding = 0) uniform ubo {
   mat4 view_projection;
   vec3 camera_position;
   vec3 light_position;
   vec3 light_color;
};

void main() {
    vec3 normal = normalize(inNormal);
    float ambient_stength = 0.1;
    vec3 ambient = ambient_stength * light_color;

    vec3 light_direction = normalize(light_position - inFragPos);
    float diffuse_strength = max(dot(normal, light_direction), 0.0);
    vec3 diffuse = diffuse_strength * light_color;

    vec3 view_direction = normalize(camera_position - inFragPos);
    vec3 reflect_direction = reflect(-light_direction, normal);
    float specular_strength = pow(max(dot(view_direction, reflect_direction), 0.0), 32);
    vec3 specular = specular_strength * light_color;
    
    vec3 result = (ambient + diffuse + specular) * inColor;
    outColor = vec4(result, 1.0);
}
