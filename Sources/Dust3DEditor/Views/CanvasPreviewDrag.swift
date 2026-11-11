import AppKit

/// Keeps a camera press out of graph input for the entire button sequence.
@MainActor
struct CanvasPreviewDrag {
    struct Target {
        let update: @MainActor (SIMD2<Float>, Bool) -> Bool
        let end: @MainActor () -> Void
    }

    typealias Begin = @MainActor () -> Target?

    private var active: (button: Int, previous: NSPoint, target: Target?)?
    var isActive: Bool { active != nil }

    static func accepts(button: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.intersection([.command, .control, .function]).isEmpty else { return false }
        return button == 2 || (button == 0 && modifiers.contains(.option))
    }

    mutating func press(
        button: Int, modifiers: NSEvent.ModifierFlags, location: NSPoint, begin: Begin
    ) -> Bool {
        if let active { return active.button == button }
        guard Self.accepts(button: button, modifiers: modifiers),
            location.x.isFinite, location.y.isFinite, let target = begin()
        else { return false }
        active = (button, location, target)
        return true
    }

    mutating func drag(button: Int, modifiers: NSEvent.ModifierFlags, location: NSPoint) -> Bool {
        guard var active, active.button == button else { return false }
        guard let target = active.target else { return true }
        let delta = SIMD2(Float(location.x - active.previous.x), Float(location.y - active.previous.y))
        active.previous = location
        if !delta.x.isFinite || !delta.y.isFinite || !target.update(delta, modifiers.contains(.shift)) {
            active.target = nil
            self.active = active
            target.end()
        } else {
            self.active = active
        }
        return true
    }

    mutating func release(button: Int) -> Bool {
        guard active?.button == button else { return false }
        cancel()
        return true
    }

    mutating func cancel() {
        let target = active?.target
        active = nil
        target?.end()
    }
}
