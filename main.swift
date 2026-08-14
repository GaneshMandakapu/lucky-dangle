//
//  Lucky Dangle (local build)
//  A lucky charm that hangs from the top of your Mac's screen.
//
//  Build:  ./build.sh      (see README.md)
//

import AppKit
import QuartzCore
import Carbon.HIToolbox

// ─────────────────────────────────────────────────────────────
// MARK: - Tuning
// ─────────────────────────────────────────────────────────────

enum Tuning {
    static let restLength: CGFloat   = 150    // normal cord length (points)
    static let dropLength: CGFloat   = 330    // length when the charm "drops in"
    static let dropSeconds: Double   = 4.0    // how long it stays dropped
    static let gravity: CGFloat      = 2000   // higher = faster swing
    static let damping: CGFloat      = 0.76   // fraction of speed kept per second
    static let maxAngle: CGFloat     = 1.15   // radians, ~66°
    static let mouseDrive: CGFloat   = 0.00022
    static let mouseDriveNear: CGFloat = 0.0011
    static let breeze: CGFloat       = 1.0    // 0 = perfectly still when idle

    static let lengthStiffness: CGFloat = 110  // cord in/out spring
    static let lengthZeta: CGFloat      = 0.72 // < 1 = a little overshoot
    static let charmLag: CGFloat        = 26   // charm swings a beat behind the cord
    static let charmLagZeta: CGFloat    = 0.55
    static let cordBow: CGFloat         = 7    // how much the cord trails when moving

    static let fallbackFrameRate: Double = 120 // only used before macOS 14
    static let physicsHz: CGFloat        = 240 // fixed integration step
}

@inline(__always) func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    min(max(v, lo), hi)
}

/// Point on a cubic Bézier.
@inline(__always) func bezier(_ p0: CGPoint, _ p1: CGPoint,
                              _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                   y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

// ─────────────────────────────────────────────────────────────
// MARK: - Charms
// ─────────────────────────────────────────────────────────────

enum Charm: String, CaseIterable {
    case nazar, clover, horseshoe, knot

    var title: String {
        switch self {
        case .nazar:     return "Nazar — evil eye (Türkiye)"
        case .clover:    return "Four-leaf clover (Ireland)"
        case .horseshoe: return "Horseshoe (Europe)"
        case .knot:      return "Lucky knot (China)"
        }
    }

    var radius: CGFloat {
        switch self {
        case .nazar: return 34
        case .clover: return 30
        case .horseshoe: return 32
        case .knot: return 30
        }
    }

    func draw(in ctx: CGContext) {
        let r = radius
        switch self {
        case .nazar:     Charm.drawNazar(ctx, r)
        case .clover:    Charm.drawClover(ctx, r)
        case .horseshoe: Charm.drawHorseshoe(ctx, r)
        case .knot:      Charm.drawKnot(ctx, r)
        }
    }

    // Each charm draws centred on (0,0), +y is up, already rotated with the cord.

    private static func circle(_ ctx: CGContext, _ r: CGFloat, _ c: NSColor,
                               _ dx: CGFloat = 0, _ dy: CGFloat = 0) {
        ctx.setFillColor(c.cgColor)
        ctx.fillEllipse(in: CGRect(x: dx - r, y: dy - r, width: r * 2, height: r * 2))
    }

    private static func drawNazar(_ ctx: CGContext, _ r: CGFloat) {
        circle(ctx, r,        NSColor(srgbRed: 0.06, green: 0.19, blue: 0.74, alpha: 1))
        circle(ctx, r * 0.66, NSColor.white)
        circle(ctx, r * 0.44, NSColor(srgbRed: 0.42, green: 0.75, blue: 0.93, alpha: 1))
        circle(ctx, r * 0.20, NSColor.black)
        ctx.setFillColor(NSColor(white: 1, alpha: 0.35).cgColor)
        ctx.fillEllipse(in: CGRect(x: -r * 0.62, y: r * 0.24,
                                   width: r * 0.34, height: r * 0.22))
    }

    private static func drawClover(_ ctx: CGContext, _ r: CGFloat) {
        // stem
        ctx.setStrokeColor(NSColor(srgbRed: 0.16, green: 0.42, blue: 0.16, alpha: 1).cgColor)
        ctx.setLineWidth(max(2, r * 0.09))
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: -r * 0.15))
        ctx.addCurve(to: CGPoint(x: r * 0.22, y: -r * 1.05),
                     control1: CGPoint(x: -r * 0.05, y: -r * 0.55),
                     control2: CGPoint(x: r * 0.25, y: -r * 0.7))
        ctx.strokePath()

        // four leaves
        for i in 0..<4 {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(i) * .pi / 2)
            let leaf = CGRect(x: -r * 0.33, y: r * 0.10, width: r * 0.66, height: r * 0.86)
            ctx.setFillColor(NSColor(srgbRed: 0.24, green: 0.62, blue: 0.24, alpha: 1).cgColor)
            ctx.fillEllipse(in: leaf)
            ctx.setFillColor(NSColor(white: 1, alpha: 0.18).cgColor)
            ctx.fillEllipse(in: leaf.insetBy(dx: r * 0.20, dy: r * 0.28)
                                    .offsetBy(dx: -r * 0.05, dy: r * 0.10))
            ctx.restoreGState()
        }
        circle(ctx, r * 0.13, NSColor(srgbRed: 0.16, green: 0.45, blue: 0.16, alpha: 1))
    }

    private static func drawHorseshoe(_ ctx: CGContext, _ r: CGFloat) {
        let ring = r * 0.62
        ctx.setLineWidth(r * 0.34)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(NSColor(srgbRed: 0.79, green: 0.64, blue: 0.16, alpha: 1).cgColor)
        ctx.beginPath()
        ctx.addArc(center: .zero, radius: ring,
                   startAngle: -0.42, endAngle: .pi + 0.42, clockwise: false)
        ctx.strokePath()

        // highlight
        ctx.setLineWidth(r * 0.10)
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.30).cgColor)
        ctx.beginPath()
        ctx.addArc(center: .zero, radius: ring + r * 0.10,
                   startAngle: 0.5, endAngle: .pi - 0.5, clockwise: false)
        ctx.strokePath()

        // nail holes
        ctx.setFillColor(NSColor(white: 0.15, alpha: 0.55).cgColor)
        for i in 0..<7 {
            let a = -0.2 + (CGFloat(i) / 6.0) * (.pi + 0.4)
            let p = CGPoint(x: cos(a) * ring, y: sin(a) * ring)
            ctx.fillEllipse(in: CGRect(x: p.x - r * 0.055, y: p.y - r * 0.055,
                                       width: r * 0.11, height: r * 0.11))
        }
    }

    private static func drawKnot(_ ctx: CGContext, _ r: CGFloat) {
        // tassel
        ctx.setStrokeColor(NSColor(srgbRed: 0.66, green: 0.13, blue: 0.11, alpha: 1).cgColor)
        ctx.setLineWidth(max(1.5, r * 0.07))
        ctx.setLineCap(.round)
        for dx in [-r * 0.14, 0, r * 0.14] {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: dx * 0.4, y: -r * 0.5))
            ctx.addLine(to: CGPoint(x: dx, y: -r * 1.15))
            ctx.strokePath()
        }

        ctx.saveGState()
        ctx.rotate(by: .pi / 4)
        let outer = CGPath(roundedRect: CGRect(x: -r * 0.60, y: -r * 0.60,
                                               width: r * 1.2, height: r * 1.2),
                           cornerWidth: r * 0.30, cornerHeight: r * 0.30, transform: nil)
        let inner = CGPath(roundedRect: CGRect(x: -r * 0.20, y: -r * 0.20,
                                               width: r * 0.4, height: r * 0.4),
                           cornerWidth: r * 0.12, cornerHeight: r * 0.12, transform: nil)
        ctx.setFillColor(NSColor(srgbRed: 0.78, green: 0.16, blue: 0.14, alpha: 1).cgColor)
        ctx.beginPath()
        ctx.addPath(outer)
        ctx.addPath(inner)
        ctx.fillPath(using: .evenOdd)

        ctx.setStrokeColor(NSColor(srgbRed: 0.95, green: 0.78, blue: 0.35, alpha: 0.9).cgColor)
        ctx.setLineWidth(max(1, r * 0.05))
        ctx.addPath(outer)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - The charm view (physics + drawing)
// ─────────────────────────────────────────────────────────────

final class CharmView: NSView {

    weak var panel: NSPanel?

    var charm: Charm = .nazar { didSet { needsDisplay = true } }

    private var theta: CGFloat = 0.10          // angle from vertical (rad)
    private var omega: CGFloat = 0             // angular velocity (rad/s)
    private var length: CGFloat = Tuning.restLength
    private var lengthVel: CGFloat = 0
    private var targetLength: CGFloat = Tuning.restLength
    private var charmAngle: CGFloat = 0.10     // charm's own angle, trails `theta`
    private var charmAngleVel: CGFloat = 0
    private var time: CGFloat = 0
    private var prevMouse: CGPoint?
    private var dragging = false
    private var dragStarted = Date()
    private var dragMoved: CGFloat = 0
    private var dropUntil: Date?

    private var lastTick: CFTimeInterval = 0
    private var accumulator: CGFloat = 0
    private let fixedDT: CGFloat = 1 / Tuning.physicsHz

    private var anchor: CGPoint { CGPoint(x: bounds.midX, y: bounds.maxY - 2) }
    private var bobRadius: CGFloat { charm.radius }
    private var bobCenter: CGPoint {
        CGPoint(x: anchor.x + sin(theta) * length,
                y: anchor.y - cos(theta) * length)
    }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Physics tick

    /// Called once per display refresh; integrates physics on a fixed step so the
    /// motion is identical at 60 Hz and 120 Hz.
    func step() {
        let now = CACurrentMediaTime()
        if lastTick == 0 { lastTick = now }
        let elapsed = CGFloat(min(now - lastTick, 0.1))   // clamp after a stall
        lastTick = now

        if let until = dropUntil, Date() >= until {
            dropUntil = nil
            targetLength = Tuning.restLength
        }

        // Mouse stirs the air. Impulse-based, so it belongs outside the fixed loop.
        let m = NSEvent.mouseLocation
        if !dragging, let prev = prevMouse, let win = panel {
            let dx = m.x - prev.x
            let a = CGPoint(x: win.frame.origin.x + anchor.x,
                            y: win.frame.origin.y + anchor.y)
            let dist = hypot(m.x - a.x, m.y - a.y)
            let prox = max(0, 1 - dist / 900)
            let drive = clamp(dx, -60, 60)
                * (Tuning.mouseDrive + Tuning.mouseDriveNear * prox)
            omega += drive / max(length / 200, 0.5)
        }
        prevMouse = m

        accumulator += elapsed
        while accumulator >= fixedDT {
            integrate(fixedDT)
            accumulator -= fixedDT
        }

        updateClickThrough()
        needsDisplay = true
    }

    private func integrate(_ h: CGFloat) {
        time += h

        // cord length: spring instead of a lerp, so drops land with a soft bounce
        let k = Tuning.lengthStiffness
        let c = 2 * sqrt(k) * Tuning.lengthZeta
        lengthVel += ((targetLength - length) * k - lengthVel * c) * h
        length += lengthVel * h

        if !dragging {
            omega += -(Tuning.gravity / max(length, 40)) * sin(theta) * h

            // a little air movement so it never looks dead
            omega += (sin(time * 0.53) * 0.021 + sin(time * 0.17 + 1.3) * 0.012)
                     * Tuning.breeze * h

            omega *= pow(Tuning.damping, h)
            theta += omega * h

            if abs(theta) > Tuning.maxAngle {
                theta = theta > 0 ? Tuning.maxAngle : -Tuning.maxAngle
                omega = -omega * 0.4
            }
        }

        // the charm hangs off the cord end and lags it slightly
        let ck = Tuning.charmLag
        let cc = 2 * sqrt(ck) * Tuning.charmLagZeta
        charmAngleVel += ((theta - charmAngle) * ck - charmAngleVel * cc) * h
        charmAngle += charmAngleVel * h
    }

    /// Click-through everywhere except right on the charm.
    private func updateClickThrough() {
        guard let win = panel else { return }
        if dragging { win.ignoresMouseEvents = false; return }
        let m = NSEvent.mouseLocation
        let b = CGPoint(x: win.frame.origin.x + bobCenter.x,
                        y: win.frame.origin.y + bobCenter.y)
        win.ignoresMouseEvents = hypot(m.x - b.x, m.y - b.y) > bobRadius + 6
    }

    // MARK: Interaction

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - bobCenter.x, p.y - bobCenter.y) <= bobRadius + 8 else { return }
        dragging = true
        dragStarted = Date()
        dragMoved = 0
        omega = 0
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        dragMoved += hypot(event.deltaX, event.deltaY)
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - anchor.x
        let dy = max(anchor.y - p.y, 8)
        let newTheta = clamp(atan2(dx, dy), -Tuning.maxAngle, Tuning.maxAngle)
        omega = (newTheta - theta) * 60 * 0.7
        theta = newTheta
        targetLength = clamp(hypot(dx, dy), Tuning.restLength * 0.7, Tuning.dropLength)
        length = targetLength
        lengthVel = 0
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        NSCursor.pop()
        if dragMoved < 4 && Date().timeIntervalSince(dragStarted) < 0.35 {
            toggleDrop()                      // a click = call it down
        } else {
            targetLength = dropUntil == nil ? Tuning.restLength : Tuning.dropLength
        }
    }

    func toggleDrop() {
        if dropUntil == nil {
            dropUntil = Date().addingTimeInterval(Tuning.dropSeconds)
            targetLength = Tuning.dropLength
            omega += 0.35
        } else {
            dropUntil = nil
            targetLength = Tuning.restLength
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        let a = anchor
        let b = bobCenter
        let dir = CGPoint(x: sin(theta), y: -cos(theta))
        let perp = CGPoint(x: cos(theta), y: sin(theta))
        let span = length - bobRadius * 0.85
        let cordEnd = CGPoint(x: a.x + dir.x * span, y: a.y + dir.y * span)

        // the cord trails behind the swing instead of staying a rigid stick
        let bow = clamp(-omega * Tuning.cordBow, -16, 16)
        let c1 = CGPoint(x: a.x + dir.x * span * 0.33 + perp.x * bow * 0.7,
                         y: a.y + dir.y * span * 0.33 + perp.y * bow * 0.7)
        let c2 = CGPoint(x: a.x + dir.x * span * 0.70 + perp.x * bow,
                         y: a.y + dir.y * span * 0.70 + perp.y * bow)

        ctx.setStrokeColor(NSColor(srgbRed: 0.61, green: 0.47, blue: 0.16, alpha: 1).cgColor)
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: a)
        ctx.addCurve(to: cordEnd, control1: c1, control2: c2)
        ctx.strokePath()

        // beads ride along the curve
        for (t, rad, color) in [(CGFloat(0.62), CGFloat(4.5), NSColor.white),
                               (CGFloat(0.72), CGFloat(6.5),
                                NSColor(srgbRed: 0.06, green: 0.19, blue: 0.74, alpha: 1)),
                               (CGFloat(0.82), CGFloat(4.5), NSColor.white)] {
            let p = bezier(a, c1, c2, cordEnd, t)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad,
                                       width: rad * 2, height: rad * 2))
        }

        // charm
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 9,
                      color: NSColor(white: 0, alpha: 0.28).cgColor)
        ctx.translateBy(x: b.x, y: b.y)
        ctx.rotate(by: -charmAngle)
        charm.draw(in: ctx)
        ctx.restoreGState()
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - Global hotkey (⌥⌘L)
// ─────────────────────────────────────────────────────────────

final class HotKey {
    static var action: (() -> Void)?
    private var ref: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            HotKey.action?()
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x4C554B59), id: 1) // 'LUKY'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - App
// ─────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var panel: NSPanel!
    private var view: CharmView!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var displayLink: Any?
    private var hotKey: HotKey?

    private var xFraction: CGFloat {
        get {
            let v = UserDefaults.standard.object(forKey: "xFraction") as? Double
            return CGFloat(v ?? 0.86)
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: "xFraction") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let w: CGFloat = 720
        let h: CGFloat = Tuning.dropLength + 120

        view = CharmView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        if let saved = UserDefaults.standard.string(forKey: "charm"),
           let c = Charm(rawValue: saved) { view.charm = c }

        panel = NSPanel(contentRect: view.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
        view.panel = panel
        reposition()
        panel.orderFrontRegardless()

        buildStatusItem()

        startTicking()

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_L),
                        modifiers: UInt32(cmdKey + optionKey)) { [weak self] in
            self?.view.toggleDrop()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reposition() }
    }

    /// Drive the animation off the display's own refresh so every frame lands on a
    /// vsync — smooth at 60 Hz and at 120 Hz on ProMotion.
    private func startTicking() {
        if #available(macOS 14.0, *) {
            let link = view.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let t = Timer(timeInterval: 1.0 / Tuning.fallbackFrameRate,
                          repeats: true) { [weak self] _ in self?.view.step() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    @objc private func tick() { view.step() }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        let w = panel.frame.width
        let x = clamp(f.minX + xFraction * f.width - w / 2, f.minX, f.maxX - w)
        panel.setFrameOrigin(NSPoint(x: x, y: f.maxY - panel.frame.height))
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "✦"

        let menu = NSMenu()

        let charmsItem = NSMenuItem(title: "Charm", action: nil, keyEquivalent: "")
        let charms = NSMenu()
        for c in Charm.allCases {
            let item = NSMenuItem(title: c.title,
                                  action: #selector(pickCharm(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c.rawValue
            item.state = (c == view.charm) ? .on : .off
            charms.addItem(item)
        }
        charmsItem.submenu = charms
        menu.addItem(charmsItem)

        let posItem = NSMenuItem(title: "Hang it", action: nil, keyEquivalent: "")
        let pos = NSMenu()
        for (name, frac) in [("Left", 0.14), ("Centre", 0.5), ("Right", 0.86)] {
            let item = NSMenuItem(title: name,
                                  action: #selector(pickPosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = frac
            pos.addItem(item)
        }
        posItem.submenu = pos
        menu.addItem(posItem)

        menu.addItem(.separator())

        let drop = NSMenuItem(title: "Drop the charm",
                              action: #selector(dropCharm), keyEquivalent: "l")
        drop.keyEquivalentModifierMask = [.command, .option]
        drop.target = self
        menu.addItem(drop)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Lucky Dangle",
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func pickCharm(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let c = Charm(rawValue: raw) else { return }
        view.charm = c
        UserDefaults.standard.set(raw, forKey: "charm")
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
    }

    @objc private func pickPosition(_ sender: NSMenuItem) {
        guard let frac = sender.representedObject as? Double else { return }
        xFraction = CGFloat(frac)
        reposition()
    }

    @objc private func dropCharm() { view.toggleDrop() }

    @objc private func quit() { NSApp.terminate(nil) }
}

// ─────────────────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
