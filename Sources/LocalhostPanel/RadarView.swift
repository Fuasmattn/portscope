import PanelCore
import SwiftUI

/// A radar scope that fills the header card. Its center sits on the card's top-right corner, so the
/// card shows one quadrant: one blip per server, and a sonar ping that expands from the corner to the
/// far edge, lighting blips as it passes.
struct RadarView: View {
    @ObservedObject var store: ServerStore
    /// Pointer position in the "panel" coordinate space, nil when the pointer is elsewhere.
    let pointer: CGPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let scopeBackground = Color(red: 0.04, green: 0.12, blue: 0.08)

    private let radius: CGFloat = 150
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
        /// Seconds since this server vanished, nil while it is alive.
        var departedAge: Double? = nil
    }

    /// Ping timing that stays continuous when the period changes (slower pings on an empty scope).
    private struct PingClock {
        var period: Double = 4
        var basePhase: Double = 0
        var epoch: Date = Date()

        /// 0 at launch, 1 when the ring reaches the far edge.
        func phase(at date: Date) -> Double {
            (basePhase + date.timeIntervalSince(epoch) / period).truncatingRemainder(dividingBy: 1)
        }

        mutating func setPeriod(_ newPeriod: Double, at date: Date) {
            guard newPeriod != period else { return }
            basePhase = phase(at: date)
            epoch = date
            period = newPeriod
        }
    }

    @State private var clock = PingClock()

    private func blip(for entry: ServerEntry) -> Blip {
        Blip(
            id: entry.id,
            port: entry.port,
            arcFraction: Double((entry.port * 47) % 97) / 96,
            radiusFraction: 0.4 + 0.55 * (Double(entry.port) * 0.6180339887).truncatingRemainder(dividingBy: 1),
            detached: entry.isDetached)
    }

    private var blips: [Blip] {
        store.collapsedEntries
            .filter { store.isShownByDefault($0) }
            .map(blip(for:))
    }

    /// Blips for servers that just vanished, fading out over 1.2 s.
    private func departedBlips(at date: Date) -> [Blip] {
        store.departed.compactMap { departure in
            let age = date.timeIntervalSince(departure.at)
            guard age >= 0, age < 1.2, store.isShownByDefault(departure.entry) else { return nil }
            var blip = blip(for: departure.entry)
            blip.departedAge = age
            return blip
        }
    }

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named("panel"))
            let currentBlips = blips
            let hovered = hoveredBlip(in: frame, blips: currentBlips)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !store.isActive || reduceMotion)) { timeline in
                Canvas { context, size in
                    drawScope(
                        &context, size: size, date: timeline.date,
                        blips: currentBlips + departedBlips(at: timeline.date))
                }
            }
            .onChange(of: hovered) { _, newValue in
                store.radarHover = newValue
            }
            .onChange(of: currentBlips.isEmpty, initial: true) { _, empty in
                // Nothing to find: pings slow down.
                clock.setPeriod(empty ? 8 : 4, at: Date())
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

    /// How far a ring travels: from the corner to the opposite corner, plus a little.
    private func reach(in size: CGSize) -> CGFloat {
        hypot(size.width, size.height) + 8
    }

    private func drawScope(_ context: inout GraphicsContext, size: CGSize, date: Date, blips: [Blip]) {
        let center = center(in: size)
        let reach = reach(in: size)

        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.scopeBackground))

        // Range rings out to the far corner, tight near the origin and widening with distance.
        for step in 1...5 {
            let fraction = pow(Double(step) / 5.5, 1.7)
            context.stroke(
                circle(center: center, radius: reach * CGFloat(fraction)),
                with: .color(phosphor.opacity(0.18)), lineWidth: 0.75)
        }

        var cross = Path()
        cross.move(to: CGPoint(x: 0, y: center.y))
        cross.addLine(to: center)
        cross.addLine(to: CGPoint(x: center.x, y: size.height))
        context.stroke(cross, with: .color(phosphor.opacity(0.12)), lineWidth: 0.75)

        let phase = reduceMotion ? 0.55 : clock.phase(at: date)
        let ring = reach * CGFloat(phase)
        drawPing(&context, center: center, radius: ring, strength: 1 - 0.6 * phase)

        // Manual ping from clicking the header rides on top of the regular one.
        if let ping = store.pingDate {
            let age = date.timeIntervalSince(ping)
            if age >= 0, age < 1.4 {
                drawPing(&context, center: center, radius: reach * CGFloat(age / 1.4), strength: 0.8 * (1 - age / 1.4))
            }
        }

        // Scanlines: faint CRT texture over everything drawn so far.
        var lines = Path()
        var y: CGFloat = 1
        while y < size.height {
            lines.move(to: CGPoint(x: 0, y: y))
            lines.addLine(to: CGPoint(x: size.width, y: y))
            y += 3
        }
        context.stroke(lines, with: .color(.black.opacity(0.14)), lineWidth: 1)

        // Seconds since the ring passed a point at this distance; negative until it arrives.
        func sincePassed(_ distance: CGFloat) -> Double {
            Double((ring - distance) / reach) * clock.period
        }

        for blip in blips {
            let (position, _) = placement(of: blip, in: size)
            let distance = hypot(position.x - center.x, position.y - center.y)
            var since = sincePassed(distance)
            if since < 0 { since += clock.period }
            // Brightest the moment the ring passes, fading until the next ping.
            let intensity = reduceMotion ? 0.9 : max(0, 1 - since / clock.period)
            let flash = (!reduceMotion && since < 0.25) ? 1 - since / 0.25 : 0
            let highlighted = store.highlightedID == blip.id
            let color = blip.detached ? Color.orange : phosphor
            var dot: CGFloat = (highlighted ? 3.5 : 2.2) + CGFloat(flash) * 1.5
            var alpha = 0.35 + 0.65 * intensity

            if flash > 0 {
                context.fill(circle(center: position, radius: dot + 5), with: .color(color.opacity(0.4 * flash)))
            }

            if blip.detached, !reduceMotion {
                // Orphans throb slowly so they stand out without a label.
                let throb = 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 2.2)
                dot += CGFloat(throb) * 1.2
                alpha = min(1, alpha + 0.25 * throb)
            }
            if let age = blip.departedAge {
                // Contact lost: fade and shrink.
                let remaining = 1 - age / 1.2
                alpha *= remaining
                dot *= CGFloat(0.5 + 0.5 * remaining)
                context.stroke(
                    circle(center: position, radius: dot + 3 + 6 * CGFloat(age / 1.2)),
                    with: .color(color.opacity(0.5 * remaining)), lineWidth: 1)
            }

            context.fill(circle(center: position, radius: dot), with: .color(color.opacity(alpha)))

            if let arrival = store.lastArrival, arrival.id == blip.id, let arrived = store.lastArrivalDate {
                let age = date.timeIntervalSince(arrived)
                if age >= 0, age < 1.6 {
                    context.stroke(
                        circle(center: position, radius: 3 + 14 * CGFloat(age / 1.6)),
                        with: .color(Color.white.opacity(1 - age / 1.6)), lineWidth: 1.5)
                }
            }
            if highlighted, blip.departedAge == nil {
                context.stroke(
                    circle(center: position, radius: dot + 4),
                    with: .color(Color.white.opacity(0.9)), lineWidth: 1)
                // Label sits up-right of the blip, flipped down or left when that would leave the card.
                let nearTop = position.y < 16
                let nearRight = position.x > size.width - 40
                context.draw(
                    Text(":\(String(blip.port))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white),
                    at: CGPoint(
                        x: nearRight ? position.x - dot - 8 : position.x + dot + 8,
                        y: nearTop ? position.y + dot + 6 : position.y - dot - 6),
                    anchor: nearRight ? .trailing : .leading)
            }
        }
    }

    /// One expanding ring: a bright thin front, two softer trailing rings, and a wide faint wake.
    private func drawPing(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, strength: Double) {
        guard radius > 0 else { return }
        context.stroke(
            circle(center: center, radius: max(0, radius - 8)),
            with: .color(phosphor.opacity(0.06 * strength)), lineWidth: 16)
        for (offset, alpha, width) in [(7.0, 0.22, 3.0), (14.0, 0.10, 3.0)] {
            let r = radius - CGFloat(offset)
            if r > 0 {
                context.stroke(circle(center: center, radius: r), with: .color(phosphor.opacity(alpha * strength)), lineWidth: width)
            }
        }
        context.stroke(circle(center: center, radius: radius), with: .color(phosphor.opacity(0.9 * strength)), lineWidth: 1.2)
        context.stroke(circle(center: center, radius: radius), with: .color(Color.white.opacity(0.35 * strength)), lineWidth: 0.5)
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
        let shown = store.collapsedEntries.filter { store.isShownByDefault($0) }

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
