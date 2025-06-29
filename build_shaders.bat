@echo off
if not exist "shaders" mkdir shaders
glslang -V src/test.frag -o shaders/test.frag.spv
glslang -V src/test.vert -o shaders/test.vert.spv
