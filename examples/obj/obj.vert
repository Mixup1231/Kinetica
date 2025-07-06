#version 450

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inTexCoord;

layout(location = 0) out vec3 outFragPos;
layout(location = 1) out vec3 outNormal;
layout(location = 2) out vec2 outTexCoord;

layout(binding = 0) uniform ubo {
   mat4 view_projection;
   vec3 camera_position;
   vec3 light_position;
   vec3 light_color;
};

void main() {
    gl_Position = view_projection * vec4(inPosition, 1.0);
    outFragPos = inPosition;
    outNormal = inNormal;
    outTexCoord = inTexCoord;
}
