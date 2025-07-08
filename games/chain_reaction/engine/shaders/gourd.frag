#version 450

layout(location = 0) in vec3 i_fragment_position;
layout(location = 1) in vec3 i_normal;
layout(location = 2) in vec2 i_uv;

layout(location = 0) out vec4 o_color;

struct Point_Light {
    vec4 position;
    vec4 color;
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

layout(binding = 2) uniform sampler2D s_albedo;
layout(binding = 3) uniform sampler2D s_emissive;

vec3 calculate_diffuse() {
    vec3 diffuse = vec3(0.0, 0.0, 0.0);
    
    for (uint i = 0; i < point_light_count; i++) {
        Point_Light light = point_lights[i];
        vec3 light_direction = normalize(light.position.xyz - i_fragment_position); 
        
        vec3 normal = normalize(i_normal);
        float diffuse_strength = max(dot(normal, light_direction), 0.0);
        
        diffuse += diffuse_strength * light.color.rgb;
    }

    return diffuse;
}

vec3 calculate_specular() {
    vec3 specular = vec3(0.0, 0.0, 0.0);

    for (uint i = 0; i < point_light_count; i++) {
        Point_Light light = point_lights[i];
        vec3 light_direction = normalize(light.position.xyz - i_fragment_position); 
        vec3 view_direction = normalize(camera_position.xyz - i_fragment_position);
        
        vec3 normal = normalize(i_normal);
        vec3 reflect_direction = reflect(-light_direction, normal);
        
        float specular_strength = pow(max(dot(view_direction, reflect_direction), 0.0), 32);
        specular += specular_strength * light.color.rgb;
    }

    return specular;
}

void main() {
    vec3 ambient = ambient_strength * ambient_color.xyz;
    vec3 diffuse = calculate_diffuse();
    vec3 specular = calculate_specular();

    o_color = vec4(ambient + diffuse + specular, 1.0) * vec4(1.0, 1.0, 1.0, 1.0);
}
