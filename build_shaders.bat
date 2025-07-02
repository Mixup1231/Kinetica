@echo off
if not exist "shaders" mkdir shaders
glslang -V examples/quad/quad.frag -o shaders/quad.frag.spv
glslang -V examples/quad/quad.vert -o shaders/quad.vert.spv
glslang -V examples/uniform/uniform.frag -o shaders/uniform.frag.spv
glslang -V examples/uniform/uniform.vert -o shaders/uniform.vert.spv
glslang -V examples/depth/depth.frag -o shaders/depth.frag.spv
glslang -V examples/depth/depth.vert -o shaders/depth.vert.spv
glslang -V examples/camera/camera.frag -o shaders/camera.frag.spv
glslang -V examples/camera/camera.vert -o shaders/camera.vert.spv
glslang -V examples/light/light.frag -o shaders/light.frag.spv
glslang -V examples/light/light.vert -o shaders/light.vert.spv
