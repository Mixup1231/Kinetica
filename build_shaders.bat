@echo off
if not exist "shaders" mkdir shaders
glslang -V examples/testing/test.frag -o shaders/test.frag.spv
glslang -V examples/testing/test.vert -o shaders/test.vert.spv
