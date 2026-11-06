import MapKit
import NutritionCore
import SwiftUI

struct RunRouteMap: View {
    let points: [RunTrackPoint]
    var followsUser = false
    @State private var camera: MapCameraPosition = .automatic

    private var segments: [[RunTrackPoint]] {
        Dictionary(grouping: points, by: \.segment).sorted { $0.key < $1.key }.map(\.value)
    }

    var body: some View {
        Map(position: $camera) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: displayed(segment).map { $0.location.coordinate })
                        .stroke(Theme.olive, lineWidth: 5)
                }
            }
            if let first = points.first {
                Marker("起点", systemImage: "flag.fill", coordinate: first.location.coordinate).tint(Theme.olive)
            }
            if !followsUser, points.count > 1, let last = points.last {
                Marker("终点", systemImage: "flag.checkered", coordinate: last.location.coordinate).tint(Theme.gold)
            }
            if followsUser { UserAnnotation() }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            if followsUser { MapUserLocationButton() }
            MapCompass()
            MapScaleView()
        }
        .onAppear {
            if followsUser { camera = .userLocation(followsHeading: false, fallback: .automatic) }
        }
        .onChange(of: followsUser) { _, follows in
            camera = follows ? .userLocation(followsHeading: false, fallback: .automatic) : .automatic
        }
        .accessibilityLabel(followsUser ? "当前位置和跑步路线地图" : "本次跑步路线地图")
    }

    private func displayed(_ segment: [RunTrackPoint]) -> [RunTrackPoint] {
        let stride = max(1, segment.count / 1500)
        guard stride > 1 else { return segment }
        var result = segment.enumerated().compactMap { $0.offset.isMultiple(of: stride) ? $0.element : nil }
        if let last = segment.last, result.last != last { result.append(last) }
        return result
    }
}

extension RunLocation {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
