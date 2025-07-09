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
glslang -V examples/texture/texture.frag -o shaders/texture.frag.spv
glslang -V examples/texture/texture.vert -o shaders/texture.vert.spv
glslang -V examples/obj/obj.frag -o shaders/obj.frag.spv
glslang -V examples/obj/obj.vert -o shaders/obj.vert.spv
glslang -V games/chain_reaction/engine/shaders/gourd.frag -o games/chain_reaction/engine/shaders/gourd.frag.spv
glslang -V games/chain_reaction/engine/shaders/gourd.vert -o games/chain_reaction/engine/shaders/gourd.vert.spv
glslang -V games/chain_reaction/engine/shaders/gourd_pixel.frag -o games/chain_reaction/engine/shaders/gourd_pixel.frag.spv
glslang -V games/chain_reaction/engine/shaders/gourd_pixel.vert -o games/chain_reaction/engine/shaders/gourd_pixel.vert.spv
