package engine

// resource manager
Max_Meshes   :: 1000
Max_Textures :: len(Texture_Type) * Max_Textures_Per_Type

// scene
Max_Entities :: 1000

// rendrer
Frames_In_Flight :: 3
Max_Models       :: Max_Entities
Vr_Eye_Count     :: 2
Num_Samplers     :: 9

// shared
Max_Textures_Per_Type :: Max_Meshes
Max_Point_Lights      :: 8
