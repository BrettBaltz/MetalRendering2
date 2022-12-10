// These globals are designed to interface between the renderer and the
// app controls (this isn't the ideal way to do this, but it is much simpler)

import simd

public class Settings {
    public var isRotatingX = false
    public var isRotatingY = false
    public var isRotatingZ = true
    
    func toggleXRotation() { isRotatingX = !isRotatingX }
    func toggleYRotation() { isRotatingY = !isRotatingY }
    func toggleZRotation() { isRotatingZ = !isRotatingZ }
}
