#version 450

layout(location = 0) in vec3 i_fragment_position;
layout(location = 1) in vec3 i_normal;
layout(location = 2) in vec2 i_uv;
layout(location = 3) in flat uint i_instance_index;

layout(location = 0) out vec4 o_color;

struct Point_Light {
    vec4 position;
    vec4 color;
};

layout(binding = 0) readonly buffer cold_ssbo {
    mat4 view_projection;
    Point_Light point_lights[8];
    vec4 camera_position;
    vec4 ambient_color;
    float ambient_strength;
    uint point_light_count;
};

layout(binding = 1) readonly buffer hot_ssbo {
    mat4 model_matrices[1000];
    uvec4 model_textures[1000];
};

layout(binding = 2) uniform sampler2D s_one;
layout(binding = 3) uniform sampler2D s_two;
layout(binding = 4) uniform sampler2D s_three;
layout(binding = 5) uniform sampler2D s_four;
layout(binding = 6) uniform sampler2D s_five;
layout(binding = 7) uniform sampler2D s_six;
layout(binding = 8) uniform sampler2D s_seven;
layout(binding = 9) uniform sampler2D s_eight;
layout(binding = 10) uniform sampler2D s_nine;

float calculate_attenuation(float distance) {
    float constant = 1.0;
    float linear = 0.09;
    float quadratic = 0.032;

    return 1.0 / (constant + linear * distance + quadratic * (distance * distance));
}

vec3 calculate_diffuse() {
    vec3 diffuse = vec3(0.0, 0.0, 0.0);

    for (uint i = 0; i < point_light_count; i++) {
        Point_Light light = point_lights[i];
        vec3 light_direction = normalize(light.position.xyz - i_fragment_position);

        vec3 normal = normalize(i_normal);
        float diffuse_strength = max(dot(normal, light_direction), 0.0);
        diffuse += diffuse_strength * light.color.rgb;
        diffuse *= calculate_attenuation(length(light.position.xyz - i_fragment_position));
    }

    return diffuse;
}

void main() {
    uint albedo_location = model_textures[i_instance_index][0];
    uint emissive_location = model_textures[i_instance_index][1];

    vec4 albedo = vec4(1.0, 1.0, 1.0, 1.0);
    if (albedo_location == 0) {
        albedo = texture(s_one, i_uv);
    } else if (albedo_location == 1) {
        albedo = texture(s_two, i_uv);
    } else if (albedo_location == 2) {
        albedo = texture(s_three, i_uv);
    } else if (albedo_location == 3) {
        albedo = texture(s_four, i_uv);
    } else if (albedo_location == 4) {
        albedo = texture(s_five, i_uv);
    } else if (albedo_location == 5) {
        albedo = texture(s_six, i_uv);
    } else if (albedo_location == 6) {
        albedo = texture(s_seven, i_uv);
    } else if (albedo_location == 7) {
        albedo = texture(s_eight, i_uv);
    } else if (albedo_location == 8) {
        albedo = texture(s_nine, i_uv);
    }

    vec4 emissive = vec4(0.0, 0.0, 0.0, 1.0);
    if (emissive_location == 0) {
        emissive = texture(s_one, i_uv);
    } else if (emissive_location == 1) {
        emissive = texture(s_two, i_uv);
    } else if (emissive_location == 2) {
        emissive = texture(s_three, i_uv);
    } else if (emissive_location == 3) {
        emissive = texture(s_four, i_uv);
    } else if (emissive_location == 4) {
        emissive = texture(s_five, i_uv);
    } else if (emissive_location == 5) {
        emissive = texture(s_six, i_uv);
    } else if (emissive_location == 6) {
        emissive = texture(s_seven, i_uv);
    } else if (emissive_location == 7) {
        emissive = texture(s_eight, i_uv);
    } else if (emissive_location == 8) {
        emissive = texture(s_nine, i_uv);
    }

    vec3 ambient = ambient_strength * ambient_color.xyz;
    vec3 diffuse = calculate_diffuse();

    float distance = length(i_fragment_position - camera_position.xyz);
    float fog_factor = 1.0 - calculate_attenuation(distance);
    vec3 fog_color = vec3(0.0, 0.0, 0.0);

    vec4 result = vec4(ambient + diffuse, 1.0) * albedo + emissive;
    vec4 final_color = mix(result, vec4(fog_color, 1.0), fog_factor);

    o_color = final_color;
}
