import PanelCore
import SwiftUI

/// A radar scope that fills the header card. Its center sits on the card's top-right corner, so the
/// card shows one quadrant: one blip per server, and a sweeping beam that lights blips as it passes.
struct RadarView: View {
    @ObservedObject var store: ServerStore
    /// Pointer position in the "panel" coordinate space, nil when the pointer is elsewhere.
    let pointer: CGPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let scopeBackground = Color(red: 0.04, green: 0.12, blue: 0.08)

    private let radius: CGFloat = 150
    private let period: Double = 4
    private let phosphor = Color(red: 0.36, green: 0.90, blue: 0.50)
    /// Keeps blips this far from the card edges.
    private let margin: CGFloat = 10

    struct Blip: Identifiable {
        let id: String
        let port: Int
        /// 0...1 along the visible arc at this blip's ring, derived from the port so a server keeps its spot.
        let arcFraction: Double
        let radiusFraction: Double
        let detached: Bool
    }

    private var blips: [Blip] {
        store.entries
            .filter { store.isShownByDefault($0) }
            .map { entry in
                Blip(
                    id: entry.id,
                    port: entry.port,
                    arcFraction: Double((entry.port * 47) % 97) / 96,
                    radiusFraction: 0.4 + 0.55 * (Double(entry.port) * 0.6180339887).truncatingRemainder(dividingBy: 1),
                    detached: entry.isDetached)
            }
    }

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named("panel"))
            let currentBlips = blips
            let hovered = hoveredBlip(in: frame, blips: currentBlips)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !store.isActive || reduceMotion)) { timeline in
                Canvas { context, size in
                    drawScope(&context, size: size, date: timeline.date, blips: currentBlips)
                }
            }
            .onChange(of: hovered) { _, newValue in
                store.radarHover = newValue
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Radar")
        .accessibilityValue("\(blips.count) servers")
    }

    // MARK: Geometry

    private func center(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width, y: 0)
    }

    /// Where a blip lands: on its ring, somewhere along the part of that ring that lies inside the card.
    /// Degrees are 0 = up, clockwise; the visible arc runs from straight down (180) to straight left (270).
    private func placement(of blip: Blip, in size: CGSize) -> (position: CGPoint, angle: Double) {
        let center = center(in: size)
        let ring = radius * CGFloat(blip.radiusFraction)
        // Angle (from the left horizontal, going down) at which this ring meets the card's bottom edge.
        let drop = min(1, max(0, (size.height - margin) / ring))
        let reach = asin(drop) * 180 / .pi
        let angle = 270 - (2 + (reach - 4) * blip.arcFraction)
        return (point(center: center, radius: ring, degrees: angle), angle)
    }

    // MARK: Pointer

    private func hoveredBlip(in frame: CGRect, blips: [Blip]) -> String? {
        guard let pointer = pointer, frame.contains(pointer) else { return nil }
        let local = CGPoint(x: pointer.x - frame.minX, y: pointer.y - frame.minY)
        var best: (id: String, distance: CGFloat)?
        for blip in blips {
            let position = placement(of: blip, in: frame.size).position
            let distance = hypot(position.x - local.x, position.y - local.y)
            if distance <= 10, distance < (best?.distance ?? .infinity) {
                best = (blip.id, distance)
            }
        }
        return best?.id
    }

    // MARK: Drawing

    private func drawScope(_ context: inout GraphicsContext, size: CGSize, date: Date, blips: [Blip]) {
        let center = center(in: size)

        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.scopeBackground))

        for fraction in [0.25, 0.5, 0.75, 1.0] {
            context.stroke(
                circle(center: center, radius: radius * CGFloat(fraction)),
                with: .color(phosphor.opacity(0.2)), lineWidth: 0.75)
        }

        var cross = Path()
        cross.move(to: CGPoint(x: center.x - radius, y: center.y))
        cross.addLine(to: CGPoint(x: center.x, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: center.y))
        cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        context.stroke(cross, with: .color(phosphor.opacity(0.14)), lineWidth: 0.75)

        let sweep = reduceMotion
            ? 230.0
            : date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * 360

        // Fading trail behind the leading edge.
        if !reduceMotion {
            for step in 0..<28 {
                var line = Path()
                line.move(to: center)
                line.addLine(to: point(center: center, radius: radius, degrees: sweep - Double(step) * 2.0))
                let alpha = 0.34 * (1 - Double(step) / 28)
                context.stroke(line, with: .color(phosphor.opacity(alpha)), lineWidth: 2.6)
            }
        }
        var lead = Path()
        lead.move(to: center)
        lead.addLine(to: point(center: center, radius: radius, degrees: sweep))
        context.stroke(lead, with: .color(phosphor.opacity(0.9)), lineWidth: 1)

        // Manual ping from clicking the header.
        if let ping = store.pingDate {
            let age = date.timeIntervalSince(ping)
            if age >= 0, age < 1.2 {
                context.stroke(
                    circle(center: center, radius: radius * CGFloat(age / 1.2)),
                    with: .color(phosphor.opacity(0.6 * (1 - age / 1.2))), lineWidth: 1.5)
            }
        }

        for blip in blips {
            let (position, angle) = placement(of: blip, in: size)
            var delta = (sweep - angle).truncatingRemainder(dividingBy: 360)
            if delta < 0 { delta += 360 }
            // Brightest just after the beam passes, fading over the rest of the rotation.
            let intensity = reduceMotion ? 0.9 : 1 - 0.7 * delta / 360
            let highlighted = store.highlightedID == blip.id
            let color = blip.detached ? Color.orange : phosphor
            let dot: CGFloat = highlighted ? 3.5 : 2.2

            context.fill(circle(center: position, radius: dot), with: .color(color.opacity(0.35 + 0.65 * intensity)))

            if let arrival = store.lastArrival, arrival.id == blip.id, let arrived = store.lastArrivalDate {
                let age = date.timeIntervalSince(arrived)
                if age >= 0, age < 1.6 {
                    context.stroke(
                        circle(center: position, radius: 3 + 14 * CGFloat(age / 1.6)),
                        with: .color(Color.white.opacity(1 - age / 1.6)), lineWidth: 1.5)
                }
            }
            if highlighted {
                context.stroke(
                    circle(center: position, radius: dot + 4),
                    with: .color(Color.white.opacity(0.9)), lineWidth: 1)
                context.draw(
                    Text(":\(String(blip.port))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white),
                    at: CGPoint(x: position.x + dot + 8, y: position.y - dot - 6),
                    anchor: .leading)
            }
        }
    }

    private func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func offset(radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = CGFloat(degrees * Double.pi / 180)
        return CGPoint(x: radius * sin(radians), y: -radius * cos(radians))
    }

    private func point(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let delta = offset(radius: radius, degrees: degrees)
        return CGPoint(x: center.x + delta.x, y: center.y + delta.y)
    }
}

/// One-line commentary that uses the real server list.
@MainActor
enum Quips {
    static func lines(for store: ServerStore) -> [String] {
        let shown = store.entries.filter { store.isShownByDefault($0) }

        if store.reaction == .alert, let arrival = store.lastArrival {
            return ["New contact on :\(arrival.port)."]
        }
        if store.reaction == .lost {
            return ["Contact lost."]
        }
        if shown.isEmpty {
            return [
                "Scope is clear. All quiet on localhost.",
                "Nothing on the scope.",
                "No contacts. Suspiciously quiet.",
            ]
        }

        var lines = ["\(shown.count) \(shown.count == 1 ? "contact" : "contacts") on the scope."]
        let oldest = shown
            .compactMap { entry in entry.uptime.map { (entry, $0) } }
            .max { $0.1 < $1.1 }
        if let (entry, uptime) = oldest, uptime > 86_400 {
            lines.append(":\(entry.port) has been up \(Formatting.uptime(uptime)). Just saying.")
        }
        if let orphan = shown.first(where: { $0.isDetached }) {
            lines.append(":\(orphan.port) is running with nobody home.")
        }
        if let exposed = shown.first(where: { !$0.loopbackOnly }) {
            lines.append(":\(exposed.port) is open to your network. Bold.")
        }
        if shown.contains(where: { $0.port == 3000 }) {
            lines.append("Port 3000 again. Classic.")
        }
        if shown.count >= 6 {
            lines.append("Busy sky. Everything okay?")
        }
        return lines
    }
}
