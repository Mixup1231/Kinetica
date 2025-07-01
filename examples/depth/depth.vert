#version 450

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;

layout(location = 0) out vec3 fragColor;

layout(binding = 0) uniform ubo {
   mat4 model;
   mat4 view;
   mat4 proj;
};

void main() {
    gl_Position = proj * view * model * vec4(inPosition, 1.0);
    fragColor = inNormal * 0.5 + 0.5;
}
