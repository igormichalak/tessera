package tessera

import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"
import "./shadercross"

Vector2 :: distinct [2]f32
FRect :: struct { x, y, w, h: f32 }
FColor :: distinct [4]f32

MAX_RECTS :: 32

VERTEX_BUFFER_SIZE :: u32(size_of(Vector2) * 4 * MAX_RECTS)
INDEX_BUFFER_SIZE :: u32(size_of(u16) * 6 * MAX_RECTS)
COLOR_BUFFER_SIZE :: u32(size_of(FColor) * MAX_RECTS)

rect_colors := [?]FColor{
	{ 0.8, 0.2, 0.2, 1.0 },
	{ 0.2, 0.8, 0.2, 1.0 },
	{ 0.2, 0.2, 0.8, 1.0 },
	{ 0.8, 0.8, 0.2, 1.0 },
	{ 0.8, 0.2, 0.8, 1.0 },
	{ 0.2, 0.8, 0.8, 1.0 },
	{ 0.9, 0.5, 0.0, 1.0 },
	{ 0.5, 0.2, 0.7, 1.0 },
}

APP_CTX :: struct {
	window: ^sdl.Window,
	device: ^sdl.GPUDevice,
	vertex_buffer: ^sdl.GPUBuffer,
	index_buffer: ^sdl.GPUBuffer,
	color_buffer: ^sdl.GPUBuffer,
	transfer_buffer: ^sdl.GPUTransferBuffer,
	debug:  bool,
}

app_ctx := APP_CTX{debug=true}

app_init :: proc() -> int {
	if !sdl.Init({.VIDEO}) {
		fmt.eprintf("Failed to initialize SDL. Error: %s\n", sdl.GetError())
		return 1
	}
	app_ctx.device = sdl.CreateGPUDevice({.SPIRV}, app_ctx.debug, nil)
	if app_ctx.device == nil {
		fmt.eprintf("Failed to create device. Error: %s\n", sdl.GetError())
		return 1
	}
	app_ctx.window = sdl.CreateWindow("Tessera Demo", 800, 600, {.RESIZABLE})
	if app_ctx.window == nil {
		fmt.eprintf("Failed to create window. Error: %s\n", sdl.GetError())
		return 1
	}
	if !sdl.ClaimWindowForGPUDevice(app_ctx.device, app_ctx.window) {
		fmt.eprintf("Failed to claim window for GPU device. Error: %s\n", sdl.GetError())
		return 1
	}

	app_ctx.vertex_buffer = sdl.CreateGPUBuffer(app_ctx.device, {
		usage = {.VERTEX},
		size = VERTEX_BUFFER_SIZE,
	})
	app_ctx.index_buffer = sdl.CreateGPUBuffer(app_ctx.device, {
		usage = {.INDEX},
		size = INDEX_BUFFER_SIZE,
	})
	app_ctx.color_buffer = sdl.CreateGPUBuffer(app_ctx.device, {
		usage = {.GRAPHICS_STORAGE_READ},
		size = COLOR_BUFFER_SIZE,
	})

	app_ctx.transfer_buffer = sdl.CreateGPUTransferBuffer(app_ctx.device, {
		usage = .UPLOAD,
		size = VERTEX_BUFFER_SIZE + INDEX_BUFFER_SIZE + COLOR_BUFFER_SIZE,
	})

	return 0
}

app_quit :: proc() {
	sdl.ReleaseGPUTransferBuffer(app_ctx.device, app_ctx.transfer_buffer)

	sdl.ReleaseGPUBuffer(app_ctx.device, app_ctx.vertex_buffer)
	sdl.ReleaseGPUBuffer(app_ctx.device, app_ctx.index_buffer)
	sdl.ReleaseGPUBuffer(app_ctx.device, app_ctx.color_buffer)

	sdl.ReleaseWindowFromGPUDevice(app_ctx.device, app_ctx.window)
	sdl.DestroyWindow(app_ctx.window)
	sdl.DestroyGPUDevice(app_ctx.device)
	sdl.Quit()
}

load_shaders :: proc(vert_filename, frag_filename: string) -> (vert_shader: ^sdl.GPUShader, frag_shader: ^sdl.GPUShader, code: int) {
	if !shadercross.Init() {
		fmt.eprintln("Failed to initalize SDL_shadercross!")
		return nil, nil, 1
	}
	defer shadercross.Quit()

	vert_raw, frag_raw: []u8
	ok: bool

	vert_raw, ok = os.read_entire_file(vert_filename)
	if !ok {
		fmt.eprintf("Failed to load file %s\n", vert_filename)
		return nil, nil, 1
	}
	defer delete(vert_raw)

	frag_raw, ok = os.read_entire_file(frag_filename)
	if !ok {
		fmt.eprintf("Failed to load file %s\n", frag_filename)
		return nil, nil, 1
	}
	defer delete(frag_raw)

	vert_info := shadercross.HLSL_Info{
		source = cstring(raw_data(vert_raw)),
		entrypoint = "main",
		defines = nil,
		shader_stage = .VERTEX,
		enable_debug = app_ctx.debug,
		name = nil,
	}
	frag_info := shadercross.HLSL_Info{
		source = cstring(raw_data(frag_raw)),
		entrypoint = "main",
		defines = nil,
		shader_stage = .FRAGMENT,
		enable_debug = app_ctx.debug,
		name = nil,
	}

	metadata: shadercross.GraphicsShaderMetadata

	vert_shader = shadercross.CompileGraphicsShaderFromHLSL(app_ctx.device, vert_info, &metadata)
	if vert_shader == nil {
		fmt.eprintln("Failed to compile vertex shader!")
		return nil, nil, 1
	}

	frag_shader = shadercross.CompileGraphicsShaderFromHLSL(app_ctx.device, frag_info, &metadata)
	if frag_shader == nil {
		fmt.eprintln("Failed to compile fragment shader!")
		return nil, nil, 1
	}

	return vert_shader, frag_shader, 0
}

create_pipeline :: proc(vert_shader, frag_shader: ^sdl.GPUShader) -> (pipeline: ^sdl.GPUGraphicsPipeline, code: int) {
	create_info := sdl.GPUGraphicsPipelineCreateInfo{
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = raw_data([]sdl.GPUColorTargetDescription{
				{
					format = sdl.GetGPUSwapchainTextureFormat(app_ctx.device, app_ctx.window),
				},
			}),
		},
		vertex_input_state = {
			num_vertex_buffers = 1,
			vertex_buffer_descriptions = raw_data([]sdl.GPUVertexBufferDescription{
				{
					slot = 0,
					input_rate = .VERTEX,
					instance_step_rate = 0,
					pitch = size_of(Vector2),
				},
			}),
			num_vertex_attributes = 1,
			vertex_attributes = raw_data([]sdl.GPUVertexAttribute{
				{
					buffer_slot = 0,
					format = .FLOAT2,
					location = 0,
					offset = 0,
				},
			}),
		},
		rasterizer_state = {
			cull_mode = .BACK,
			front_face = .CLOCKWISE,
		},
		primitive_type = .TRIANGLELIST,
		vertex_shader = vert_shader,
		fragment_shader = frag_shader,
	}
	pipeline = sdl.CreateGPUGraphicsPipeline(app_ctx.device, create_info)
	if pipeline == nil {
		fmt.eprintf("Failed to create graphics pipeline. Error: %s\n", sdl.GetError())
		return nil, 1
	}
	return pipeline, 0
}

clip_space :: proc(position, viewport: Vector2) -> Vector2 {
	return { (position.x / viewport.x * 2 - 1), -(position.y / viewport.y * 2 - 1) }
}

draw :: proc(pipeline: ^sdl.GPUGraphicsPipeline, rects: []FRect) -> int {
	cmd_buf := sdl.AcquireGPUCommandBuffer(app_ctx.device)
	if cmd_buf == nil {
		fmt.eprintf("Failed to acquire GPU command buffer. Error: %s\n", sdl.GetError())
		return 1
	}

	swapchain_texture: ^sdl.GPUTexture
	vw, vh: u32

	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, app_ctx.window, &swapchain_texture, &vw, &vh) {
		fmt.eprintf("Failed to acquire GPU swapchain texture. Error: %s\n", sdl.GetError())
		if !sdl.CancelGPUCommandBuffer(cmd_buf) {
			fmt.eprintf("Failed to cancel GPU command buffer. Error: %s\n", sdl.GetError())
		}
		return 1
	}

	viewport := Vector2{f32(vw), f32(vh)}

	transfer_ptr := sdl.MapGPUTransferBuffer(app_ctx.device, app_ctx.transfer_buffer, true)

	vertex_data := cast([^]Vector2)transfer_ptr
	index_data  := cast([^]u16)rawptr(uintptr(transfer_ptr) + uintptr(VERTEX_BUFFER_SIZE))
	color_data  := cast([^]FColor)rawptr(uintptr(transfer_ptr) + uintptr(VERTEX_BUFFER_SIZE + INDEX_BUFFER_SIZE))

	for rect, idx in rects {
		idx4 := idx * 4
		vertex_data[idx4 + 0] = clip_space({ (rect.x         ), (rect.y         ) }, viewport)
		vertex_data[idx4 + 1] = clip_space({ (rect.x + rect.w), (rect.y         ) }, viewport)
		vertex_data[idx4 + 2] = clip_space({ (rect.x + rect.w), (rect.y + rect.h) }, viewport)
		vertex_data[idx4 + 3] = clip_space({ (rect.x         ), (rect.y + rect.h) }, viewport)

		idx6 := idx * 6
		index_data[idx6 + 0] = u16(idx4 + 0)
		index_data[idx6 + 1] = u16(idx4 + 1)
		index_data[idx6 + 2] = u16(idx4 + 2)
		index_data[idx6 + 3] = u16(idx4 + 0)
		index_data[idx6 + 4] = u16(idx4 + 2)
		index_data[idx6 + 5] = u16(idx4 + 3)

		color_data[idx] = rect_colors[idx % len(rect_colors)]
	}

	sdl.UnmapGPUTransferBuffer(app_ctx.device, app_ctx.transfer_buffer)

	copy_pass := sdl.BeginGPUCopyPass(cmd_buf)

	sdl.UploadToGPUBuffer(copy_pass, {
		transfer_buffer = app_ctx.transfer_buffer,
		offset = 0,
	}, {
		buffer = app_ctx.vertex_buffer,
		offset = 0,
		size = u32(size_of(Vector2) * 4 * len(rects)),
	}, true)

	sdl.UploadToGPUBuffer(copy_pass, {
		transfer_buffer = app_ctx.transfer_buffer,
		offset = VERTEX_BUFFER_SIZE,
	}, {
		buffer = app_ctx.index_buffer,
		offset = 0,
		size = u32(size_of(u16) * 6 * len(rects)),
	}, true)

	sdl.UploadToGPUBuffer(copy_pass, {
		transfer_buffer = app_ctx.transfer_buffer,
		offset = VERTEX_BUFFER_SIZE + INDEX_BUFFER_SIZE,
	}, {
		buffer = app_ctx.color_buffer,
		offset = 0,
		size = u32(size_of(FColor) * len(rects)),
	}, true)

	sdl.EndGPUCopyPass(copy_pass)

	color_target_info := sdl.GPUColorTargetInfo{
		texture = swapchain_texture,
		clear_color = { 0.1, 0.1, 0.1, 1.0 },
		load_op = .CLEAR,
		store_op = .STORE,
	}

	render_pass := sdl.BeginGPURenderPass(cmd_buf, raw_data([]sdl.GPUColorTargetInfo{color_target_info}), 1, nil)

	sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
	sdl.BindGPUVertexBuffers(render_pass, 0, raw_data([]sdl.GPUBufferBinding{
		{
			buffer = app_ctx.vertex_buffer,
			offset = 0,
		},
	}), 1)
	sdl.BindGPUVertexStorageBuffers(render_pass, 0, raw_data([]^sdl.GPUBuffer{app_ctx.color_buffer}), 1)
	sdl.BindGPUIndexBuffer(render_pass, {
		buffer = app_ctx.index_buffer,
		offset = 0,
	}, ._16BIT)
	sdl.DrawGPUIndexedPrimitives(render_pass, u32(6 * len(rects)), 1, 0, 0, 0)

	sdl.EndGPURenderPass(render_pass)

	if !sdl.SubmitGPUCommandBuffer(cmd_buf) {
		fmt.eprintf("Failed to submit GPU command buffer. Error: %s\n", sdl.GetError())
		return 1
	}

	return 0
}

run :: proc() -> (code: int) {
	if code = app_init(); code > 0 do return code
	defer app_quit()

	vert_shader, frag_shader: ^sdl.GPUShader
	vert_shader, frag_shader, code = load_shaders(
		"./Shaders/Rectangles.vert.hlsl",
		"./Shaders/Rectangles.frag.hlsl",
	)
	if code > 0 do return code

	pipeline: ^sdl.GPUGraphicsPipeline
	pipeline, code = create_pipeline(vert_shader, frag_shader)
	if code > 0 do return code
	defer sdl.ReleaseGPUGraphicsPipeline(app_ctx.device, pipeline)

	sdl.ReleaseGPUShader(app_ctx.device, vert_shader)
	sdl.ReleaseGPUShader(app_ctx.device, frag_shader)

	rects := make([dynamic]FRect, 0, 8)
	defer delete(rects)

	append(&rects, FRect{
		x = 10,
		y = 10,
		w = 60,
		h = 30,
	})
	append(&rects, FRect{
		x = 140,
		y = 170,
		w = 80,
		h = 90,
	})

	should_close := false
	for !should_close {
		e: sdl.Event
		for sdl.PollEvent(&e) {
			#partial switch(e.type) {
			case .QUIT:
				should_close = true
			}
		}
		draw(pipeline, rects[:])
	}

	return 0
}

main :: proc() {
	code := run()
	os.exit(code)
}
