//
//  Lucky Dangle (local build)
//  A lucky charm that hangs from the top of your Mac's screen.
//
//  Build:  ./build.sh      (see README.md)
//

import AppKit
import Carbon.HIToolbox

// ─────────────────────────────────────────────────────────────
// MARK: - Tuning
// ─────────────────────────────────────────────────────────────

enum Tuning {
    static let restLength: CGFloat   = 190    // normal cord length (points)
    static let dropLength: CGFloat   = 400    // length when the charm "drops in"
    static let dropSeconds: Double   = 4.0    // how long it stays dropped
    static let gravity: CGFloat      = 2000   // higher = faster swing
    static let damping: CGFloat      = 0.9955 // closer to 1 = swings longer
    static let maxAngle: CGFloat     = 1.15   // radians, ~66°
    static let mouseDrive: CGFloat   = 0.00022
    static let mouseDriveNear: CGFloat = 0.0011
    static let breeze: CGFloat       = 1.0    // 0 = perfectly still when idle
    static let frameRate: Double     = 60

    // Shine
    static let glintPeriod: CGFloat  = 4.2    // seconds between glint sweeps
    static let glintTravel: CGFloat  = 1.15   // seconds a sweep takes
    static let glowStrength: CGFloat = 1.0    // 0 = no halo
    static let sparkles: Bool        = true
}

let dt: CGFloat = CGFloat(1.0 / Tuning.frameRate)

@inline(__always) func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    min(max(v, lo), hi)
}

@inline(__always) func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                            _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

// ─────────────────────────────────────────────────────────────
// MARK: - Drawing helpers
// ─────────────────────────────────────────────────────────────

func gradient(_ stops: [(NSColor, CGFloat)]) -> CGGradient? {
    let colors = stops.map { ($0.0.usingColorSpace(.sRGB) ?? $0.0).cgColor } as CFArray
    return CGGradient(colorsSpace: sRGBSpace, colors: colors,
                      locations: stops.map { $0.1 })
}

/// Fill a path with a radial gradient, lit from `center`.
func fillRadial(_ ctx: CGContext, _ path: CGPath, center: CGPoint,
                radius: CGFloat, _ stops: [(NSColor, CGFloat)]) {
    guard let g = gradient(stops) else { return }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius,
                           options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
    ctx.restoreGState()
}

/// Fill a path with a linear gradient running along `angle`.
func fillLinear(_ ctx: CGContext, _ path: CGPath, angle: CGFloat,
                extent: CGFloat, _ stops: [(NSColor, CGFloat)]) {
    guard let g = gradient(stops) else { return }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let d = CGPoint(x: cos(angle) * extent, y: sin(angle) * extent)
    ctx.drawLinearGradient(g, start: CGPoint(x: -d.x, y: -d.y), end: d,
                           options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
    ctx.restoreGState()
}

/// A soft blurred-looking specular blob (fake blur via a radial fade).
func specular(_ ctx: CGContext, at p: CGPoint, size: CGFloat,
              squash: CGFloat = 0.62, angle: CGFloat = -0.5, alpha: CGFloat = 0.6) {
    guard let g = gradient([(srgb(1, 1, 1, alpha), 0),
                            (srgb(1, 1, 1, alpha * 0.45), 0.45),
                            (srgb(1, 1, 1, 0), 1)]) else { return }
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: angle)
    ctx.scaleBy(x: 1, y: squash)
    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0,
                           endCenter: .zero, endRadius: size, options: [])
    ctx.restoreGState()
}

/// Four-point sparkle centred on the origin.
func starPath(_ s: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k = s * 0.16
    p.move(to: CGPoint(x: 0, y: s))
    p.addQuadCurve(to: CGPoint(x: s, y: 0), control: CGPoint(x: k, y: k))
    p.addQuadCurve(to: CGPoint(x: 0, y: -s), control: CGPoint(x: k, y: -k))
    p.addQuadCurve(to: CGPoint(x: -s, y: 0), control: CGPoint(x: -k, y: -k))
    p.addQuadCurve(to: CGPoint(x: 0, y: s), control: CGPoint(x: -k, y: k))
    p.closeSubpath()
    return p
}

/// Light state handed to the charm each frame.
struct Shine {
    let time: CGFloat
    let energy: CGFloat   // 0…1, how hard it's swinging
    let enabled: Bool
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

    var baseRadius: CGFloat {
        switch self {
        case .nazar: return 58
        case .clover: return 52
        case .horseshoe: return 54
        case .knot: return 52
        }
    }

    /// Colour of the glow halo.
    var tint: NSColor {
        switch self {
        case .nazar:     return srgb(0.25, 0.50, 1.00)
        case .clover:    return srgb(0.35, 0.85, 0.35)
        case .horseshoe: return srgb(1.00, 0.82, 0.30)
        case .knot:      return srgb(1.00, 0.32, 0.26)
        }
    }

    // MARK: Full render

    func draw(in ctx: CGContext, r: CGFloat, shine: Shine) {
        let sil = silhouette(r)
        drawShadowAndGlow(ctx, sil, r, shine)
        drawBody(ctx, r)
        if shine.enabled {
            drawGlint(ctx, sil, r, shine)
            if Tuning.sparkles { drawSparkles(ctx, r, shine) }
        }
    }

    // MARK: Silhouette — used for the glow, the glint clip and the halo

    func silhouette(_ r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        switch self {
        case .nazar:
            p.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        case .clover:
            for i in 0..<4 {
                let t = CGAffineTransform(rotationAngle: CGFloat(i) * .pi / 2)
                p.addEllipse(in: CGRect(x: -r * 0.33, y: r * 0.10,
                                        width: r * 0.66, height: r * 0.86),
                             transform: t)
            }
            p.addEllipse(in: CGRect(x: -r * 0.16, y: -r * 0.16,
                                    width: r * 0.32, height: r * 0.32))
        case .horseshoe:
            let arc = CGMutablePath()
            arc.addArc(center: .zero, radius: r * 0.62,
                       startAngle: -0.42, endAngle: .pi + 0.42, clockwise: false)
            return arc.copy(strokingWithWidth: r * 0.34, lineCap: .round,
                            lineJoin: .round, miterLimit: 10)
        case .knot:
            let t = CGAffineTransform(rotationAngle: .pi / 4)
            p.addRoundedRect(in: CGRect(x: -r * 0.60, y: -r * 0.60,
                                        width: r * 1.2, height: r * 1.2),
                             cornerWidth: r * 0.30, cornerHeight: r * 0.30,
                             transform: t)
        }
        return p
    }

    // MARK: Depth — drop shadow plus a coloured halo

    private func drawShadowAndGlow(_ ctx: CGContext, _ sil: CGPath,
                                   _ r: CGFloat, _ shine: Shine) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12,
                      color: srgb(0, 0, 0, 0.30).cgColor)
        ctx.setFillColor(srgb(0, 0, 0, 1).cgColor)
        ctx.addPath(sil)
        ctx.fillPath()
        ctx.restoreGState()

        guard shine.enabled, Tuning.glowStrength > 0 else { return }
        let pulse = 0.5 + 0.5 * sin(shine.time * 1.6)
        let a = (0.30 + 0.22 * pulse + 0.28 * shine.energy) * Tuning.glowStrength
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 16 + 14 * shine.energy + 6 * pulse,
                      color: tint.withAlphaComponent(min(a, 0.85)).cgColor)
        ctx.setFillColor(tint.cgColor)
        ctx.addPath(sil)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: Bodies

    private func drawBody(_ ctx: CGContext, _ r: CGFloat) {
        switch self {
        case .nazar:     drawNazar(ctx, r)
        case .clover:    drawClover(ctx, r)
        case .horseshoe: drawHorseshoe(ctx, r)
        case .knot:      drawKnot(ctx, r)
        }
    }

    private func drawNazar(_ ctx: CGContext, _ r: CGFloat) {
        let lit = CGPoint(x: -r * 0.34, y: r * 0.34)

        let glass = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2),
                           transform: nil)
        fillRadial(ctx, glass, center: lit, radius: r * 1.9,
                   [(srgb(0.34, 0.56, 1.00), 0.00),
                    (srgb(0.11, 0.30, 0.88), 0.42),
                    (srgb(0.04, 0.13, 0.58), 0.80),
                    (srgb(0.02, 0.07, 0.36), 1.00)])

        let white = CGPath(ellipseIn: CGRect(x: -r * 0.66, y: -r * 0.66,
                                             width: r * 1.32, height: r * 1.32),
                           transform: nil)
        fillRadial(ctx, white, center: CGPoint(x: -r * 0.2, y: r * 0.2), radius: r * 1.1,
                   [(srgb(1, 1, 1), 0), (srgb(0.94, 0.96, 0.99), 0.6),
                    (srgb(0.82, 0.86, 0.92), 1)])

        let iris = CGPath(ellipseIn: CGRect(x: -r * 0.44, y: -r * 0.44,
                                            width: r * 0.88, height: r * 0.88),
                          transform: nil)
        fillRadial(ctx, iris, center: CGPoint(x: -r * 0.14, y: r * 0.16), radius: r * 0.8,
                   [(srgb(0.62, 0.88, 1.00), 0), (srgb(0.36, 0.72, 0.94), 0.5),
                    (srgb(0.13, 0.44, 0.78), 1)])

        let pupil = CGPath(ellipseIn: CGRect(x: -r * 0.20, y: -r * 0.20,
                                             width: r * 0.40, height: r * 0.40),
                           transform: nil)
        fillRadial(ctx, pupil, center: CGPoint(x: -r * 0.06, y: r * 0.07), radius: r * 0.4,
                   [(srgb(0.16, 0.17, 0.22), 0), (srgb(0.02, 0.02, 0.05), 1)])

        // inner rim shading, then the glass hot-spots
        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        ctx.setStrokeColor(srgb(0, 0, 0, 0.28).cgColor)
        ctx.setLineWidth(r * 0.10)
        ctx.addPath(glass)
        ctx.strokePath()
        ctx.restoreGState()

        specular(ctx, at: CGPoint(x: -r * 0.44, y: r * 0.46), size: r * 0.40,
                 squash: 0.55, angle: -0.55, alpha: 0.75)
        specular(ctx, at: CGPoint(x: r * 0.38, y: -r * 0.46), size: r * 0.22,
                 squash: 0.6, angle: -0.5, alpha: 0.35)
    }

    private func drawClover(_ ctx: CGContext, _ r: CGFloat) {
        ctx.setStrokeColor(srgb(0.14, 0.40, 0.15).cgColor)
        ctx.setLineWidth(max(2, r * 0.09))
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: -r * 0.15))
        ctx.addCurve(to: CGPoint(x: r * 0.22, y: -r * 1.05),
                     control1: CGPoint(x: -r * 0.05, y: -r * 0.55),
                     control2: CGPoint(x: r * 0.25, y: -r * 0.7))
        ctx.strokePath()

        for i in 0..<4 {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(i) * .pi / 2)
            let leafRect = CGRect(x: -r * 0.33, y: r * 0.10,
                                  width: r * 0.66, height: r * 0.86)
            let leaf = CGPath(ellipseIn: leafRect, transform: nil)
            fillRadial(ctx, leaf, center: CGPoint(x: -r * 0.10, y: r * 0.42),
                       radius: r * 0.75,
                       [(srgb(0.52, 0.86, 0.40), 0), (srgb(0.26, 0.66, 0.26), 0.55),
                        (srgb(0.11, 0.42, 0.14), 1)])
            // vein
            ctx.setStrokeColor(srgb(0.09, 0.34, 0.11, 0.5).cgColor)
            ctx.setLineWidth(max(1, r * 0.035))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: r * 0.16))
            ctx.addLine(to: CGPoint(x: 0, y: r * 0.88))
            ctx.strokePath()
            specular(ctx, at: CGPoint(x: -r * 0.12, y: r * 0.62), size: r * 0.20,
                     squash: 0.7, angle: 0.3, alpha: 0.45)
            ctx.restoreGState()
        }

        let hub = CGPath(ellipseIn: CGRect(x: -r * 0.15, y: -r * 0.15,
                                           width: r * 0.30, height: r * 0.30),
                         transform: nil)
        fillRadial(ctx, hub, center: CGPoint(x: -r * 0.04, y: r * 0.05), radius: r * 0.3,
                   [(srgb(0.34, 0.70, 0.30), 0), (srgb(0.10, 0.36, 0.12), 1)])
    }

    private func drawHorseshoe(_ ctx: CGContext, _ r: CGFloat) {
        let sil = silhouette(r)
        fillLinear(ctx, sil, angle: 1.15, extent: r,
                   [(srgb(1.00, 0.93, 0.66), 0.00),
                    (srgb(0.93, 0.76, 0.28), 0.35),
                    (srgb(0.72, 0.53, 0.12), 0.70),
                    (srgb(0.52, 0.36, 0.07), 1.00)])

        // polished inner band
        ctx.saveGState()
        ctx.addPath(sil)
        ctx.clip()
        ctx.setLineWidth(r * 0.10)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(srgb(1, 0.98, 0.86, 0.55).cgColor)
        ctx.beginPath()
        ctx.addArc(center: .zero, radius: r * 0.70,
                   startAngle: 0.30, endAngle: .pi - 0.30, clockwise: false)
        ctx.strokePath()
        ctx.setStrokeColor(srgb(0.35, 0.24, 0.04, 0.45).cgColor)
        ctx.beginPath()
        ctx.addArc(center: .zero, radius: r * 0.50,
                   startAngle: 0.20, endAngle: .pi - 0.20, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()

        // nail holes
        for i in 0..<7 {
            let a = -0.2 + (CGFloat(i) / 6.0) * (.pi + 0.4)
            let p = CGPoint(x: cos(a) * r * 0.62, y: sin(a) * r * 0.62)
            let hole = CGPath(ellipseIn: CGRect(x: p.x - r * 0.058, y: p.y - r * 0.058,
                                                width: r * 0.116, height: r * 0.116),
                              transform: nil)
            fillRadial(ctx, hole, center: CGPoint(x: p.x, y: p.y + r * 0.03),
                       radius: r * 0.12,
                       [(srgb(0.30, 0.21, 0.05), 0), (srgb(0.10, 0.07, 0.01), 1)])
        }
    }

    private func drawKnot(_ ctx: CGContext, _ r: CGFloat) {
        ctx.setStrokeColor(srgb(0.62, 0.11, 0.10).cgColor)
        ctx.setLineWidth(max(1.5, r * 0.07))
        ctx.setLineCap(.round)
        for dx in [-r * 0.16, 0, r * 0.16] {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: dx * 0.4, y: -r * 0.5))
            ctx.addLine(to: CGPoint(x: dx, y: -r * 1.15))
            ctx.strokePath()
        }

        let t = CGAffineTransform(rotationAngle: .pi / 4)
        let outer = CGPath(roundedRect: CGRect(x: -r * 0.60, y: -r * 0.60,
                                               width: r * 1.2, height: r * 1.2),
                           cornerWidth: r * 0.30, cornerHeight: r * 0.30, transform: nil)
        let inner = CGPath(roundedRect: CGRect(x: -r * 0.20, y: -r * 0.20,
                                               width: r * 0.4, height: r * 0.4),
                           cornerWidth: r * 0.12, cornerHeight: r * 0.12, transform: nil)

        ctx.saveGState()
        ctx.concatenate(t)
        ctx.addPath(outer)
        ctx.addPath(inner)
        ctx.clip(using: .evenOdd)
        if let g = gradient([(srgb(1.00, 0.44, 0.36), 0.00),
                             (srgb(0.85, 0.19, 0.16), 0.50),
                             (srgb(0.52, 0.06, 0.06), 1.00)]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: -r * 0.25, y: r * 0.25),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: -r * 0.25, y: r * 0.25),
                                   endRadius: r * 1.4,
                                   options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()

        ctx.saveGState()
        ctx.concatenate(t)
        ctx.setStrokeColor(srgb(1.00, 0.85, 0.45, 0.95).cgColor)
        ctx.setLineWidth(max(1, r * 0.055))
        ctx.addPath(outer)
        ctx.strokePath()
        ctx.setStrokeColor(srgb(1.00, 0.85, 0.45, 0.6).cgColor)
        ctx.addPath(inner)
        ctx.strokePath()
        ctx.restoreGState()

        specular(ctx, at: CGPoint(x: -r * 0.26, y: r * 0.30), size: r * 0.30,
                 squash: 0.55, angle: -0.7, alpha: 0.5)
    }

    // MARK: Shimmer — a band of light sweeping across the charm

    private func drawGlint(_ ctx: CGContext, _ sil: CGPath,
                           _ r: CGFloat, _ shine: Shine) {
        // sweeps more often the harder it swings
        let period = Tuning.glintPeriod - 2.2 * shine.energy
        let phase = shine.time.truncatingRemainder(dividingBy: max(period, 1.0))
        guard phase < Tuning.glintTravel else { return }

        let p = phase / Tuning.glintTravel                 // 0…1 across the charm
        let ease = sin(p * .pi)                            // fade in and out
        let intensity = (0.45 + 0.35 * shine.energy) * ease
        let x = (p * 2 - 1) * r * 1.9

        guard let g = gradient([(srgb(1, 1, 1, 0), 0),
                                (srgb(1, 1, 1, intensity * 0.55), 0.42),
                                (srgb(1, 1, 1, intensity), 0.5),
                                (srgb(1, 1, 1, intensity * 0.55), 0.58),
                                (srgb(1, 1, 1, 0), 1)]) else { return }

        ctx.saveGState()
        ctx.addPath(sil)
        ctx.clip()
        ctx.setBlendMode(.plusLighter)
        ctx.rotate(by: -0.62)                              // diagonal band
        let w = r * 0.85
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: x - w, y: 0),
                               end: CGPoint(x: x + w, y: 0),
                               options: [])
        ctx.restoreGState()

        // the leading edge throws a spark
        if p > 0.35 && p < 0.75 {
            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            ctx.translateBy(x: x * 0.5, y: r * 0.34)
            ctx.rotate(by: -0.62)
            ctx.setFillColor(srgb(1, 1, 1, intensity * 0.9).cgColor)
            ctx.addPath(starPath(r * 0.34))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    private func drawSparkles(_ ctx: CGContext, _ r: CGFloat, _ shine: Shine) {
        let spots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-0.62,  0.58, 0.26, 0.0),
            ( 0.70,  0.14, 0.20, 1.9),
            ( 0.18, -0.72, 0.17, 3.4),
        ]
        for (sx, sy, scale, offset) in spots {
            let cycle: CGFloat = 3.1
            let t = (shine.time + offset).truncatingRemainder(dividingBy: cycle)
            guard t < 0.8 else { continue }
            let a = sin(t / 0.8 * .pi)
            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            ctx.translateBy(x: sx * r, y: sy * r)
            ctx.rotate(by: t * 1.2)
            ctx.setFillColor(srgb(1, 1, 1, a * (0.55 + 0.35 * shine.energy)).cgColor)
            ctx.addPath(starPath(r * scale * (0.6 + 0.4 * a)))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - The charm view (physics + drawing)
// ─────────────────────────────────────────────────────────────

final class CharmView: NSView {

    weak var panel: NSPanel?

    var charm: Charm = .nazar { didSet { needsDisplay = true } }
    var sizeScale: CGFloat = 1.0 { didSet { needsDisplay = true } }
    var shimmer: Bool = true { didSet { needsDisplay = true } }

    private var theta: CGFloat = 0.10          // angle from vertical (rad)
    private var omega: CGFloat = 0             // angular velocity (rad/s)
    private var length: CGFloat = Tuning.restLength
    private var targetLength: CGFloat = Tuning.restLength
    private var time: CGFloat = 0
    private var prevMouse: CGPoint?
    private var dragging = false
    private var dragStarted = Date()
    private var dragMoved: CGFloat = 0
    private var dropUntil: Date?

    private var anchor: CGPoint { CGPoint(x: bounds.midX, y: bounds.maxY - 2) }
    private var bobRadius: CGFloat { charm.baseRadius * sizeScale }
    private var bobCenter: CGPoint {
        CGPoint(x: anchor.x + sin(theta) * length,
                y: anchor.y - cos(theta) * length)
    }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Physics tick

    func step() {
        time += dt

        if let until = dropUntil, Date() >= until {
            dropUntil = nil
            targetLength = Tuning.restLength
        }
        length += (targetLength - length) * 0.10

        if !dragging {
            omega += -(Tuning.gravity / max(length, 40)) * sin(theta) * dt

            omega += (sin(time * 0.53) * 0.00035 + sin(time * 0.17 + 1.3) * 0.0002)
                     * Tuning.breeze

            let m = NSEvent.mouseLocation
            if let prev = prevMouse, let win = panel {
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

            omega *= Tuning.damping
            theta += omega * dt

            if abs(theta) > Tuning.maxAngle {
                theta = theta > 0 ? Tuning.maxAngle : -Tuning.maxAngle
                omega = -omega * 0.4
            }
        }

        updateClickThrough()
        needsDisplay = true
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
        omega = (newTheta - theta) * CGFloat(Tuning.frameRate) * 0.7
        theta = newTheta
        targetLength = clamp(hypot(dx, dy), Tuning.restLength * 0.7, Tuning.dropLength)
        length = targetLength
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
        let a = anchor
        let b = bobCenter
        let r = bobRadius
        let dir = CGPoint(x: sin(theta), y: -cos(theta))
        let cordEnd = CGPoint(x: a.x + dir.x * (length - r * 0.85),
                              y: a.y + dir.y * (length - r * 0.85))
        let energy = min(1, abs(omega) / 2.2)
        let shine = Shine(time: time, energy: energy, enabled: shimmer)

        // cord — dark core with a lit edge
        ctx.setLineCap(.round)
        ctx.setStrokeColor(srgb(0.42, 0.31, 0.09).cgColor)
        ctx.setLineWidth(2.6)
        ctx.beginPath()
        ctx.move(to: a)
        ctx.addLine(to: cordEnd)
        ctx.strokePath()
        ctx.setStrokeColor(srgb(0.93, 0.79, 0.40, 0.85).cgColor)
        ctx.setLineWidth(1.0)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: a.x - 0.5, y: a.y))
        ctx.addLine(to: CGPoint(x: cordEnd.x - 0.5, y: cordEnd.y))
        ctx.strokePath()

        // beads
        let beads: [(CGFloat, CGFloat, [(NSColor, CGFloat)])] = [
            (0.60, r * 0.13, [(srgb(1, 1, 1), 0), (srgb(0.78, 0.80, 0.86), 1)]),
            (0.71, r * 0.19, [(srgb(0.42, 0.62, 1.00), 0), (srgb(0.05, 0.14, 0.60), 1)]),
            (0.82, r * 0.13, [(srgb(1, 1, 1), 0), (srgb(0.78, 0.80, 0.86), 1)]),
        ]
        for (t, rad, stops) in beads {
            let p = CGPoint(x: a.x + (cordEnd.x - a.x) * t, y: a.y + (cordEnd.y - a.y) * t)
            let path = CGPath(ellipseIn: CGRect(x: p.x - rad, y: p.y - rad,
                                                width: rad * 2, height: rad * 2),
                              transform: nil)
            fillRadial(ctx, path, center: CGPoint(x: p.x - rad * 0.35, y: p.y + rad * 0.35),
                       radius: rad * 1.8, stops)
        }

        // charm
        ctx.saveGState()
        ctx.translateBy(x: b.x, y: b.y)
        ctx.rotate(by: -theta)
        charm.draw(in: ctx, r: r, shine: shine)
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
    private var hotKey: HotKey?

    private let sizes: [(String, CGFloat)] = [("Small", 0.75), ("Medium", 1.0),
                                              ("Large", 1.3), ("Huge", 1.6)]

    private var xFraction: CGFloat {
        get {
            let v = UserDefaults.standard.object(forKey: "xFraction") as? Double
            return CGFloat(v ?? 0.86)
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: "xFraction") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let w: CGFloat = 980
        let h: CGFloat = Tuning.dropLength + 230

        view = CharmView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "charm"), let c = Charm(rawValue: saved) {
            view.charm = c
        }
        if let s = defaults.object(forKey: "sizeScale") as? Double {
            view.sizeScale = CGFloat(s)
        }
        if let sh = defaults.object(forKey: "shimmer") as? Bool {
            view.shimmer = sh
        }

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

        let t = Timer(timeInterval: 1.0 / Tuning.frameRate, repeats: true) { [weak self] _ in
            self?.view.step()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_L),
                        modifiers: UInt32(cmdKey + optionKey)) { [weak self] in
            self?.view.toggleDrop()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reposition() }
    }

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

        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (name, scale) in sizes {
            let item = NSMenuItem(title: name,
                                  action: #selector(pickSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Double(scale)
            item.state = abs(scale - view.sizeScale) < 0.01 ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

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

        let shimmer = NSMenuItem(title: "Shimmer",
                                 action: #selector(toggleShimmer(_:)), keyEquivalent: "")
        shimmer.target = self
        shimmer.state = view.shimmer ? .on : .off
        menu.addItem(shimmer)

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

    @objc private func pickSize(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? Double else { return }
        view.sizeScale = CGFloat(s)
        UserDefaults.standard.set(s, forKey: "sizeScale")
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
    }

    @objc private func pickPosition(_ sender: NSMenuItem) {
        guard let frac = sender.representedObject as? Double else { return }
        xFraction = CGFloat(frac)
        reposition()
    }

    @objc private func toggleShimmer(_ sender: NSMenuItem) {
        view.shimmer.toggle()
        sender.state = view.shimmer ? .on : .off
        UserDefaults.standard.set(view.shimmer, forKey: "shimmer")
    }

    @objc private func dropCharm() { view.toggleDrop() }

    @objc private func quit() { NSApp.terminate(nil) }
}

// ─────────────────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
