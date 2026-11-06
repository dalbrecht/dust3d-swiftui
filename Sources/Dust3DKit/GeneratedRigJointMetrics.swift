extension GeneratedRigJoint {
    /// Grounded endpoint distance in model units. Convert before subtracting so
    /// finite Float endpoints cannot overflow an intermediate Float difference.
    package var lengthInModelUnits: Double {
        let x = Double(tail.x) - Double(head.x)
        let y = Double(tail.y) - Double(head.y)
        let z = Double(tail.z) - Double(head.z)
        return (x * x + y * y + z * z).squareRoot()
    }

    /// Read-only presentation conversion; retains sign and never evaluates a pose.
    package var closingAngleDegrees: Double { Double(closingAngle) * 180 / Double.pi }
}
