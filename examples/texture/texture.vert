#version 450

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;

layout(location = 0) out vec2 outTexCoord;

layout(binding = 0) uniform ubo {
   mat4 view_projection;
};

void main() {
    gl_Position = view_projection * vec4(inPosition, 1.0);
    outTexCoord = inTexCoord;
}
