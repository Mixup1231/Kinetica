#version 450

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;

layout(location = 0) out vec3 fragColor;
layout(location = 1) out vec3 outFragPos;
layout(location = 2) out vec3 outNormal;

layout(binding = 0) uniform ubo {
   mat4 view_projection;
   vec3 camera_position;
   vec3 light_position;
   vec3 light_color;
};

void main() {
    gl_Position = view_projection * vec4(inPosition, 1.0);
    outFragPos = inPosition;
    fragColor = inNormal * 0.5 + 0.5;
    outNormal = inNormal;
}
