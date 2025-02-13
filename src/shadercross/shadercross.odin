package shadercross

import "core:c"
import sdl "vendor:sdl3"

Uint8  :: u8
Uint32 :: u32

ShaderStage :: enum c.int {
	VERTEX,
	FRAGMENT,
	COMPUTE,
}

GraphicsShaderMetadata :: struct {
	num_samplers:         Uint32,
	num_storage_textures: Uint32,
	num_storage_buffers:  Uint32,
	num_uniform_buffers:  Uint32,

	props: sdl.PropertiesID,
}

ComputePipelineMetadata :: struct {
	num_samplers:                   Uint32,
	num_readonly_storage_textures:  Uint32,
	num_readonly_storage_buffers:   Uint32,
	num_readwrite_storage_textures: Uint32,
	num_readwrite_storage_buffers:  Uint32,
	num_uniform_buffers:            Uint32,
	threadcount_x:                  Uint32,
	threadcount_y:                  Uint32,
	threadcount_z:                  Uint32,

	props: sdl.PropertiesID,
}

SPIRV_Info :: struct {
	bytecode:      [^]Uint8,
	bytecode_size: uint,
	entrypoint:    cstring,
	shader_stage:  ShaderStage,
	enable_debug:  bool,
	name:          cstring,

	props: sdl.PropertiesID,
}

HLSL_Define :: struct {
	name:  cstring,
	value: cstring,
}

HLSL_Info :: struct {
	source:       cstring,
	entrypoint:   cstring,
	include_dir:  cstring,
	defines:      [^]HLSL_Define,
	shader_stage: ShaderStage,
	enable_debug: bool,
	name:         cstring,

	props: sdl.PropertiesID,
}

foreign import lib "system:SDL3_shadercross"

@(default_calling_convention="c", link_prefix="SDL_ShaderCross_", require_results)
foreign lib {
	Init                          :: proc() -> bool ---
	Quit                          :: proc() ---
	GetSPIRVShaderFormats         :: proc() -> sdl.GPUShaderFormat ---
	GetHLSLShaderFormats          :: proc() -> sdl.GPUShaderFormat ---
	CompileGraphicsShaderFromHLSL :: proc(device: ^sdl.GPUDevice, #by_ptr info: HLSL_Info, metadata: ^GraphicsShaderMetadata) -> ^sdl.GPUShader ---
}
