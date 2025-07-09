#version 450

layout(location = 1) in vec2 i_uv;

layout(location = 0) out vec4 o_color;

layout(binding = 0) uniform pixel{
    vec2 resolution;
    float pixel_size;
};

layout(binding = 1) uniform sampler2D u_texture;

void main() {
    vec2 uv_pixel_size = pixel_size / resolution;
    vec2 pixel_index = floor(i_uv / uv_pixel_size);
    vec2 pixel_center = (pixel_index + 0.5) * uv_pixel_size;

    o_color = texture(u_texture, pixel_center);
}
