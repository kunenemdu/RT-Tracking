import Foundation
import MapKit
import Combine

// MARK: - GeoJSON Codable Structs

/// Top-level container for a GeoJSON FeatureCollection.
struct GeoJSONFeatureCollection: Decodable {
    let type: String
    let features: [GeoJSONFeature]
}

/// Represents a single GeoJSON Feature.
struct GeoJSONFeature: Decodable {
    let type: String
    let properties: GeoJSONProperties
    let geometry: GeoJSONGeometry
}

/// Properties of a GeoJSON Feature, specifically for bus routes.
struct GeoJSONProperties: Decodable {
    let route_id: String
    let route_short_name: String? // Optional, useful for debugging/display
    let route_long_name: String?  // Optional
}

/// Geometry of a GeoJSON Feature. We are interested in LineString.
struct GeoJSONGeometry: Decodable {
    let type: String
    let coordinates: [[Double]] // For LineString, it's an array of [longitude, latitude] pairs
}

// MARK: - RouteGeoJSONManager

/// Manages loading and providing MKPolyline data from a GeoJSON file.
final class RouteGeoJSONManager: ObservableObject {
    private var routePolylines: [String: MKPolyline] = [:] // Cache for polylines keyed by route_id

    /// Loads and parses the GeoJSON file, populating the cache.
    /// - Parameter filename: The name of the GeoJSON file in the app bundle (e.g., "bus_routes").
    func loadGeoJSON(filename: String) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "geojson") else {
            print("Error: GeoJSON file '\(filename).geojson' not found in bundle.")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let featureCollection = try decoder.decode(GeoJSONFeatureCollection.self, from: data)

            // Process each feature and create an MKPolyline
            for feature in featureCollection.features {
                guard feature.geometry.type == "LineString" else {
                    print("Warning: Skipping non-LineString geometry type: \(feature.geometry.type)")
                    continue
                }

                let routeId = feature.properties.route_id
                let coordinates = feature.geometry.coordinates

                // Convert [longitude, latitude] to [CLLocationCoordinate2D]
                let mapCoordinates = coordinates.map { rawCoord in
                    CLLocationCoordinate2D(latitude: rawCoord[1], longitude: rawCoord[0])
                }

                // Create MKPolyline and cache it
                let polyline = MKPolyline(coordinates: mapCoordinates, count: mapCoordinates.count)
                routePolylines[routeId] = polyline
            }
            print("Successfully loaded \(routePolylines.count) routes from \(filename).geojson")

        } catch {
            print("Error loading or parsing GeoJSON file '\(filename).geojson': \(error)")
        }
    }

    /// Retrieves an `MKPolyline` for a given `route_id`.
    /// - Parameter routeId: The ID of the route to retrieve.
    /// - Returns: An `MKPolyline` if found, otherwise `nil`.
    func polylineForRoute(id routeId: String) -> MKPolyline? {
        return routePolylines[routeId]
    }
}

