#version 450

layout(location = 0) out vec4 outColor;

layout(location = 0) in vec2 inTexCoord;

layout(binding = 1) uniform sampler2D texSampler;

void main() {
    outColor = texture(texSampler, inTexCoord);
}
