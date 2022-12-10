import Foundation
import MetalKit
import simd

let textureFiles = ["mini_body_diffuse.png", "mini_body_spec.png",
                    "mini_brakes_diffuse.png", "mini_parts_diffuse.png",
                    "mini_parts_spec.png", "mini_rims_diffuse.png",
                    "mini_tires_diffuse.png", "mini-flags.png"]

class Renderer: NSObject, MTKViewDelegate {
    let parent: MetalView
    var metalDevice: MTLDevice!
    let metalCommandQueue: MTLCommandQueue!
    let depthStencilState: MTLDepthStencilState
    let pipelineState: MTLRenderPipelineState
    let geometry: Geometry
    var materials: [String: Material] = [:]
    var vertexUniforms: VertexUniforms
    var fragmentUniforms: FragmentUniforms
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let uniformVertexBuffer: MTLBuffer
    let uniformFragmentBuffer: MTLBuffer
    var textures: [String: MTLTexture] = [:]
    
    init(_ parent: MetalView) {
        // Configure the GPU
        self.parent = parent
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        }
        // Schedules command buffers to the GPU 
        self.metalCommandQueue = metalDevice.makeCommandQueue()
        let library = metalDevice.makeDefaultLibrary()
        
        // Create a pipeline descriptor which will be used to configure
        // a pipeline state
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library?.makeFunction(
            name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library?.makeFunction(
            name: "fragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        // Set the vertex attribute array
        let vertexDescriptor = MTLVertexDescriptor()
        let SIZE_FLOAT3 = MemoryLayout<simd_float3>.stride
        vertexDescriptor.attributes[0].format = .float3          // Position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3          // Normal
        vertexDescriptor.attributes[1].offset = SIZE_FLOAT3
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float2          // Tex coord
        vertexDescriptor.attributes[2].offset = SIZE_FLOAT3 * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
    
        // Bind the vertex attribute array and build the pipeline state
        // from the pipeline descriptor
        // The pipeline state configures the behavior of a render command
        try! pipelineState = metalDevice.makeRenderPipelineState(
            descriptor: pipelineDescriptor)
        
        // Set the DepthStencilDescriptor so that primvitives are rendered
        // according to z value instead of the painter's algorithm
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilState = metalDevice.makeDepthStencilState(
            descriptor: depthStencilDescriptor)!
        
        // Read geometry data from file
        var path = Bundle.main.path(
            forResource: "mini_geometry",
            ofType: "json"
        )!
        var data = FileManager().contents(atPath: path)!
        try! geometry = JSONDecoder().decode(Geometry.self, from: data)
        
        // Read materials data from file
        path = Bundle.main.path(forResource: "mini_material", ofType: "json")!
        data = FileManager().contents(atPath: path)!
        try! materials = JSONDecoder().decode(
            Dictionary<String, Material>.self,
            from: data
        )
        
        // Create vertices based on structure of vertexdata
        var vertices: [Vertex] = []
        for i in stride(from: 0, to: geometry.vertexdata.count, by: 8) {
            let vertex = Vertex(
                position: simd_float3(geometry.vertexdata[i ... i + 2]),
                normal: simd_float3(geometry.vertexdata[i + 3 ... i + 5]),
                texCoord: simd_float2(geometry.vertexdata[i + 6 ... i + 7])
            )
            vertices.append(vertex)
        }
        
        // Define matrices for transforming positions from local coordinates
        // to world coordinates
        var modelMatrix = createIdentityMatrix()
        modelMatrix = rotateByX(mat: modelMatrix, rad: toRad(60))
        let viewMatrix = lookAt(
            eye: simd_float3(0, 0, -1),
            center: simd_float3(0, 0, 0),
            up: simd_float3(0, 1, 0)
        )
        let projectionMatrix = ortho(
            left:   -200, right: 200,
            bottom: -200, top:   200,
            near:   -200, far:   200
        )
        
        // Store matrices as uniforms for access by the vertex shader
        vertexUniforms = VertexUniforms(
            modelMatrix: modelMatrix,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix
        )
        
        // Store color as a uniform for access by the fragment shader
        // The value will be updated in draw
        fragmentUniforms = FragmentUniforms(color: simd_float3(0.0, 0.0, 0.0))
        
        // Reserve GPU memory for information that must be shared
        // with the shaders
        vertexBuffer = metalDevice.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: []
        )!
        indexBuffer = metalDevice.makeBuffer(
            bytes: geometry.indexdata,
            length: geometry.indexdata.count * MemoryLayout<UInt16>.stride,
            options: []
        )!
        uniformVertexBuffer = metalDevice.makeBuffer(
            bytes: &vertexUniforms,
            length: MemoryLayout<VertexUniforms>.stride,
            options: []
        )!
        uniformFragmentBuffer = metalDevice.makeBuffer(
            bytes: &fragmentUniforms,
            length: MemoryLayout<FragmentUniforms>.stride,
            options: []
        )!
    
        super.init()
        
        // Configure options on how to load each texture
        let textureOptions: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.flippedVertically,
            .generateMipmaps: true
        ]
        
        // Load each texture and store in a dictionary for reference in draw
        textures = [:]
        for i in stride(from: 0, to: textureFiles.count, by: 1) {
            let dir = "textures/"
            let newTexture = loadTexture(filename: dir + textureFiles[i],
                                         options: textureOptions)
            textures[textureFiles[i]] = newTexture
        }
    }
    
    func draw(in view: MTKView) {
        // Drawable is the area to which the GPU is to render the sequence
        // of draw calls stored in the command buffer
        guard let drawable = view.currentDrawable
        else { return }
        // Stores the sequence of draw calls which the GPU is to render
        // once it is commited
        let commandBuffer = metalCommandQueue.makeCommandBuffer()!
        
        // Configures the output attachments of a render pass
        let renderPassDescriptor = view.currentRenderPassDescriptor!
        renderPassDescriptor.colorAttachments[0].clearColor =
            MTLClearColorMake(1.0, 1.0, 1.0, 1.0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        // Encode rendering commands into the command buffer
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        
        // Give the shaders access to the memory regions the GPU has
        // reserved
        renderEncoder.setVertexBuffer(
            vertexBuffer,
            offset: 0,
            index: 0
        )
        renderEncoder.setVertexBuffer(
            uniformVertexBuffer,
            offset: 0,
            index: 1
        )
        renderEncoder.setFragmentBuffer(
            uniformFragmentBuffer,
            offset: 0,
            index: 0
        )
        
        // Perform rotations according to app controls
        if settings.isRotatingX {
            vertexUniforms.modelMatrix = rotateByX(
                mat: vertexUniforms.modelMatrix,
                rad: toRad(0.5)
            )
        }
        if settings.isRotatingY {
            vertexUniforms.modelMatrix = rotateByY(
                mat: vertexUniforms.modelMatrix,
                rad: toRad(0.5)
            )
        }
        if settings.isRotatingZ {
            vertexUniforms.modelMatrix = rotateByZ(
                mat: vertexUniforms.modelMatrix,
                rad: toRad(0.5)
            )
        }
        
        // Save matrix transforms for access by the vertex shader
        uniformVertexBuffer.contents().copyMemory(
            from: &vertexUniforms,
            byteCount: MemoryLayout<VertexUniforms>.stride
        )
        
        // Draw each part by drawing the primitives which comprise it
        for (part, indices) in geometry.groups {
            // Bind diffuse texture for the part if it exists
            let diffuseTexture = (materials[part]?.diffuse == "") ?
                                  nil : textures[(materials[part]?.diffuse)!]
            renderEncoder.setFragmentTexture(diffuseTexture, index: 0)
            
            // Bind specular texture for the part if it exists
            let specularTexture = (materials[part]?.specular == "") ?
                                   nil : textures[(materials[part]?.specular)!]
            renderEncoder.setFragmentTexture(specularTexture, index: 1)
            
            // Copy new color to memory for access by the fragment shader
            fragmentUniforms.color = (materials[part]?.color)!
            uniformFragmentBuffer.contents().copyMemory(
                from: &fragmentUniforms,
                byteCount: MemoryLayout<FragmentUniforms>.stride
            )
            
            // Encode the draw command in the command buffer
            // for future rendering
            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: (indices[1] - indices[0]) * 3,
                indexType: .uint16,
                indexBuffer: indexBuffer,
                indexBufferOffset: indices[0] * 3 * MemoryLayout<UInt16>.stride
            )
        }
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    // Load a texture from a file according to the options provided
    func loadTexture(filename: String,
                     options: [MTKTextureLoader.Option : Any])
    -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: metalDevice)
        let url = Bundle.main.url(forResource: filename, withExtension: nil)!
        
        let newTexture: MTLTexture
        try! newTexture = textureLoader.newTexture(URL: url, options: options)
        return newTexture
    }
}
