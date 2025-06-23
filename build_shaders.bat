@echo off

glslang -V src/test.frag -o shaders/test.frag.spv
glslang -V src/test.vert -o shaders/test.vert.spv
