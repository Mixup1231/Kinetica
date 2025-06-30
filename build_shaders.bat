@echo off
if not exist "shaders" mkdir shaders
glslang -V examples/quad/quad.frag -o shaders/quad.frag.spv
glslang -V examples/quad/quad.vert -o shaders/quad.vert.spv
