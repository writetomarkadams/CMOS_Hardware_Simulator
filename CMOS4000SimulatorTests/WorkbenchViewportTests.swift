import CoreGraphics
import Testing
@testable import CMOS4000Simulator

struct WorkbenchViewportTests {
    @Test func zoomKeepsTheSameWorldPointUnderTheCursorAtBothLimits() {
        var viewport = WorkbenchViewport()
        viewport.pan(x: -40, y: 30)
        let cursor = CGPoint(x: 240, y: 160)
        let originalPoint = viewport.worldPoint(at: cursor)

        viewport.zoom(to: 9, around: cursor)
        #expect(viewport.scale == 4)
        #expect(viewport.worldPoint(at: cursor) == originalPoint)

        viewport.zoom(to: 0.01, around: cursor)
        #expect(viewport.scale == 0.25)
        #expect(viewport.worldPoint(at: cursor) == originalPoint)

        viewport.zoom(to: 1, around: cursor)
        #expect(viewport.worldPoint(at: cursor) == originalPoint)
    }

    @Test func fitCentersOffsetBoundsWithPadding() {
        var viewport = WorkbenchViewport()
        let bounds = CGRect(x: -80, y: 950, width: 400, height: 200)
        viewport.fit(bounds, in: CGSize(width: 856, height: 656))

        #expect(viewport.scale == 2)
        #expect(viewport.worldPoint(at: CGPoint(x: 428, y: 328)) == CGPoint(x: 120, y: 1050))
        #expect(viewport.worldPoint(at: CGPoint(x: 28, y: 128)) == bounds.origin)
    }
}


struct WorkbenchWireRoutingTests {
    @Test func previewAndCompletedRouteKeepEveryWaypoint() {
        let start = CGPoint(x: 3, y: 7)
        let bends = [CGPoint(x: 40, y: 20), CGPoint(x: 10, y: 50)]
        let end = CGPoint(x: 100, y: 82)
        let wire = WorkbenchWire(id: 1, first: .junction(2), second: .junction(3), bends: bends)
        let preview = WorkbenchWire.gridRoute(from: start, through: bends)
        let route = wire.route(from: start, to: end)
        #expect(Array(route.prefix(preview.count)) == preview)
        #expect(route.first == start)
        #expect(route.last == end)
        #expect(bends.allSatisfy(route.contains))
        #expect(zip(route, route.dropFirst()).allSatisfy { $0.x == $1.x || $0.y == $1.y })
    }

    @Test func generatedRouteUsesGridLanesBetweenOffGridPinLeads() {
        let start = CGPoint(x: 17, y: 23)
        let end = CGPoint(x: 92, y: 53)
        let wire = WorkbenchWire(id: 1, first: .junction(2), second: .junction(3),
                                 bends: [], netName: "Generated")
        let route = wire.route(from: start, to: end)
        #expect(route.first == start)
        #expect(route.last == end)
        for (a, b) in zip(route, route.dropFirst()) {
            #expect(a.x == b.x || a.y == b.y)
            if abs(a.x - b.x) + abs(a.y - b.y) > WorkbenchWire.gridSpacing {
                #expect((a.x == b.x && a.x == WorkbenchWire.snap(a).x) ||
                        (a.y == b.y && a.y == WorkbenchWire.snap(a).y))
            }
        }
    }

    @Test func detourAvoidsRetracingTheIncomingLegAtABend() {
        let bend = CGPoint(x: 0, y: 40)
        let end = CGPoint(x: 10, y: 0)
        #expect(WorkbenchWire.orthogonalRoute(from: .zero, through: [bend, end]) ==
                [.zero, bend, CGPoint(x: 10, y: 40), end])
    }

    @Test func importedSegmentStaysStraightUntilItsPinMoves() {
        let start = CGPoint(x: 20, y: 30)
        let end = CGPoint(x: 90, y: 30)
        let wire = WorkbenchWire(id: 1, first: .junction(2), second: .junction(3), bends: [], sourceRoute: .straight)
        #expect(wire.route(from: start, to: end) == [start, end])

        let moved = CGPoint(x: 100, y: 75)
        let route = wire.route(from: start, to: moved)
        #expect(route == [start, CGPoint(x: 100, y: 30), moved])
        var viewport = WorkbenchViewport()
        viewport.pan(x: 25, y: -125)
        viewport.zoom(to: 2, around: .zero)
        let projected = route.map { point in
            CGPoint(x: point.x * viewport.scale + viewport.origin.x,
                    y: point.y * viewport.scale + viewport.origin.y)
        }
        #expect(zip(projected, projected.dropFirst()).allSatisfy { $0.x == $1.x || $0.y == $1.y })
    }
}
