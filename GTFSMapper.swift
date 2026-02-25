import Foundation
import MapKit

// New struct to hold summarized route information for display/mapping
// Made public as it will be used outside GTFSMapper
public struct GTFSRouteInfo: Identifiable, Hashable, Decodable {
    public let id: String // Corresponds to route_id
    public let shortName: String // Corresponds to route_short_name
    public let longName: String  // Corresponds to route_long_name

    enum CodingKeys: String, CodingKey {
        case id = "route_id"
        case shortName = "route_short_name"
        case longName = "route_long_name"
    }
}

// Moved GTFSStop to top-level to allow it to be used by the Actor and Structs easily
struct GTFSStop: Decodable {
    let stop_id: String
    let stop_name: String?
    let stop_lat: Double
    let stop_lon: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: stop_lat, longitude: stop_lon)
    }
    
    enum CodingKeys: String, CodingKey {
        case stop_id, stop_name, stop_lat, stop_lon
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringId = try? container.decode(String.self, forKey: .stop_id) {
            stop_id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .stop_id) {
            stop_id = String(intId)
        } else {
            throw DecodingError.typeMismatch(String.self, .init(codingPath: [CodingKeys.stop_id], debugDescription: "stop_id not string/int"))
        }
        stop_name = try? container.decode(String.self, forKey: .stop_name)
        stop_lat = try container.decode(Double.self, forKey: .stop_lat)
        stop_lon = try container.decode(Double.self, forKey: .stop_lon)
    }
}

// New struct to represent the mapped route
struct MappedRoute: CustomStringConvertible {
    let routeId: String
    let routeShortName: String
    let routeLongName: String
    let direction0TripId: String?
    let direction0Stops: [GTFSStop]
    let direction1TripId: String?
    let direction1Stops: [GTFSStop]
    
    var description: String {
        var output = "\n[GTFS] FINAL MAPPING for Route: \(routeShortName) (\(routeLongName))\n"
        output += "- Route ID: \(routeId)\n"
        
        if let tripId0 = direction0TripId {
            output += "- Direction 0 (Trip: \(tripId0)) -> stops (\(direction0Stops.count))\n"
            for stop in direction0Stops {
                output += "    • stop_id: \(stop.stop_id), name: \(stop.stop_name ?? "(none)"), lat: \(stop.stop_lat), lon: \(stop.stop_lon)\n"
            }
        }
        
        if let tripId1 = direction1TripId {
            output += "- Direction 1 (Trip: \(tripId1)) -> stops (\(direction1Stops.count))\n"
            for stop in direction1Stops {
                output += "    • stop_id: \(stop.stop_id), name: \(stop.stop_name ?? "(none)"), lat: \(stop.stop_lat), lon: \(stop.stop_lon)\n"
            }
        }
        return output
    }
}

/// A utility to build and print mapping from route -> trips -> stops.
/// Converted to an actor for thread-safe caching and safe concurrent access.
actor GTFSMapper {
    
    static let shared = GTFSMapper()
    private init() {}

    // MARK: - Internal GTFS Models
    private struct GTFSRoute: Decodable {
        let route_id: String
        let route_short_name: String
        let route_long_name: String
    }
    
    private struct GTFSTrip: Decodable {
        let route_id: String
        let trip_id: String
        let direction_id: Int
        
        enum CodingKeys: String, CodingKey { case route_id, trip_id, direction_id }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            route_id = try container.decode(String.self, forKey: .route_id)
            trip_id = try container.decode(String.self, forKey: .trip_id)
            if let intVal = try? container.decode(Int.self, forKey: .direction_id) {
                direction_id = intVal
            } else if let strVal = try? container.decode(String.self, forKey: .direction_id), let intVal = Int(strVal) {
                direction_id = intVal
            } else {
                throw DecodingError.typeMismatch(Int.self, .init(codingPath: [CodingKeys.direction_id], debugDescription: "Invalid direction_id"))
            }
        }
    }

    // MARK: - Caching
    private var cachedStops: [GTFSStop]?
    private var cachedRoutes: [GTFSRoute]?
    private var cachedTrips: [GTFSTrip]?
    private var cachedStopTimes: [String: [String]]?
    private var cachedMappedRoutes: [String: MappedRoute] = [:]
    private var cachedStopToRoutes: [String: [GTFSRouteInfo]]?
    private var cachedGeoJSONRoutes: GeoJSONFeatureCollection?
    private var cachedRoutePolylines: [String: MKPolyline] = [:]
    private var cachedSnappedPolylines: [String: MKPolyline] = [:]

    // MARK: - Dataset Loader Helpers
    private func loadStops() throws -> [GTFSStop] {
        if let s = cachedStops { return s }
        cachedStops = try loadJSON(filename: "stops")
        return cachedStops!
    }
    private func loadRoutes() throws -> [GTFSRoute] {
        if let r = cachedRoutes { return r }
        cachedRoutes = try loadJSON(filename: "routes")
        return cachedRoutes!
    }
    private func loadTrips() throws -> [GTFSTrip] {
        if let t = cachedTrips { return t }
        cachedTrips = try loadJSON(filename: "trips")
        return cachedTrips!
    }
    private func loadStopTimes() throws -> [String: [String]] {
        if let st = cachedStopTimes { return st }
        cachedStopTimes = try loadJSON(filename: "stop_times")
        return cachedStopTimes!
    }

    // MARK: - Public API
    
    func run(routeId: String) async -> MappedRoute? {
        if let cached = cachedMappedRoutes[routeId] { return cached }
        do {
            let stops = try loadStops()
            let routes = try loadRoutes()
            let trips = try loadTrips()
            let stopTimes = try loadStopTimes()
            
            guard let route = routes.first(where: { $0.route_id == routeId }) else { return nil }
            
            let stopsById = Dictionary(uniqueKeysWithValues: stops.map { ($0.stop_id, $0) })
            
            var d0Id: String?, d0Stops: [GTFSStop] = []
            var d1Id: String?, d1Stops: [GTFSStop] = []
            
            if let t0 = trips.first(where: { $0.route_id == routeId && $0.direction_id == 0 }) {
                d0Id = t0.trip_id
                d0Stops = (stopTimes[t0.trip_id] ?? []).compactMap { stopsById[$0] }
            }
            if let t1 = trips.first(where: { $0.route_id == routeId && $0.direction_id == 1 }) {
                d1Id = t1.trip_id
                d1Stops = (stopTimes[t1.trip_id] ?? []).compactMap { stopsById[$0] }
            }
            
            let mapped = MappedRoute(
                routeId: routeId,
                routeShortName: route.route_short_name,
                routeLongName: route.route_long_name,
                direction0TripId: d0Id,
                direction0Stops: d0Stops,
                direction1TripId: d1Id,
                direction1Stops: d1Stops
            )
            cachedMappedRoutes[routeId] = mapped
            return mapped
        } catch {
            return nil
        }
    }

    func generateStopToRouteMapping() async -> [String: [GTFSRouteInfo]]? {
        if let cached = cachedStopToRoutes { return cached }
        do {
            let routes = try loadRoutes()
            let trips = try loadTrips()
            let stopTimes = try loadStopTimes()
            
            let infoById = Dictionary(uniqueKeysWithValues: routes.map {
                ($0.route_id, GTFSRouteInfo(id: $0.route_id, shortName: $0.route_short_name, longName: $0.route_long_name))
            })
            
            var map: [String: Set<GTFSRouteInfo>] = [:]
            for trip in trips {
                if let info = infoById[trip.route_id], let sids = stopTimes[trip.trip_id] {
                    for sid in sids { map[sid, default: []].insert(info) }
                }
            }
            let result = map.mapValues { Array($0).sorted { $0.shortName < $1.shortName } }
            cachedStopToRoutes = result
            return result
        } catch {
            return nil
        }
    }

    // MARK: - GeoJSON Polyline Loading
    
    private struct GeoJSONFeatureCollection: Decodable {
        let features: [GeoJSONFeature]
    }
    private struct GeoJSONFeature: Decodable {
        let properties: Properties
        let geometry: Geometry
        struct Properties: Decodable {
            let route: Route
            struct Route: Decodable { let route_id: String? }
        }
        struct Geometry: Decodable {
            let type: String
            let coordinates: [[Double]]
        }
    }

    private func loadGeoJSONRoutes() async throws -> GeoJSONFeatureCollection {
        if let cached = cachedGeoJSONRoutes { return cached }
        let collection: GeoJSONFeatureCollection = try loadJSON(filename: "77780211", fileExtension: "geojson")
        cachedGeoJSONRoutes = collection
        return collection
    }

    func loadRoutePolyline(forRouteId routeId: String) async -> MKPolyline? {
        if let cached = cachedRoutePolylines[routeId] { return cached }
        do {
            let collection = try await loadGeoJSONRoutes()
            guard let feature = collection.features.first(where: { 
                $0.properties.route.route_id == routeId && $0.geometry.type == "LineString"
            }) else { return nil }
            
            let coords = feature.geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            cachedRoutePolylines[routeId] = polyline
            return polyline
        } catch {
            return nil
        }
    }

    // MARK: - Strict Snapping Logic

    /// Loads a road-snapped polyline.
    /// STRICT: If road-snapping fails, it uses high-res GeoJSON shape coordinates for that segment 
    /// instead of a straight line, ensuring buildings are never crossed.
    func loadSnappedRoutePolyline(forRouteId routeId: String) async -> MKPolyline? {
        if let cached = cachedSnappedPolylines[routeId] { return cached }
        
        let rawPolyline = await loadRoutePolyline(forRouteId: routeId)
        guard let mappedRoute = await run(routeId: routeId) else { return rawPolyline }
        
        let stops = mappedRoute.direction0Stops.isEmpty ? mappedRoute.direction1Stops : mappedRoute.direction0Stops
        guard stops.count > 1 else { return rawPolyline }
        
        var allPoints: [MKMapPoint] = []
        
        for i in 0..<(stops.count - 1) {
            let source = stops[i].coordinate
            let destination = stops[i+1].coordinate
            
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = .automobile
            
            let directions = MKDirections(request: request)
            
            do {
                let response = try await directions.calculate()
                if let route = response.routes.first {
                    let pts = route.polyline.points
                    for j in 0..<route.polyline.pointCount {
                        appendPointIfUnique(pts()[j], to: &allPoints)
                    }
                }
            } catch {
                // STRICT FALLBACK: Use high-res GTFS shape points between stops
                if let raw = rawPolyline {
                    let segment = getRawPointsBetween(source: source, destination: destination, in: raw)
                    for pt in segment { appendPointIfUnique(pt, to: &allPoints) }
                } else {
                    appendPointIfUnique(MKMapPoint(source), to: &allPoints)
                    appendPointIfUnique(MKMapPoint(destination), to: &allPoints)
                }
            }
            await Task.yield()
        }
        
        guard !allPoints.isEmpty else { return nil }
        let finalPolyline = MKPolyline(points: allPoints, count: allPoints.count)
        cachedSnappedPolylines[routeId] = finalPolyline
        return finalPolyline
    }

    private func appendPointIfUnique(_ point: MKMapPoint, to array: inout [MKMapPoint]) {
        if let last = array.last, last.x == point.x && last.y == point.y { return }
        array.append(point)
    }

    private func getRawPointsBetween(source: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, in rawPolyline: MKPolyline) -> [MKMapPoint] {
        let pts = rawPolyline.points
        let count = rawPolyline.pointCount
        var sIdx = 0, eIdx = 0
        var sDist = Double.infinity, eDist = Double.infinity
        let sP = MKMapPoint(source), eP = MKMapPoint(destination)
        
        for i in 0..<count {
            let dS = sP.distance(to: pts()[i])
            if dS < sDist { sDist = dS; sIdx = i }
            let dE = eP.distance(to: pts()[i])
            if dE < eDist { eDist = dE; eIdx = i }
        }
        
        var segment: [MKMapPoint] = []
        if sIdx <= eIdx {
            for i in sIdx...eIdx { segment.append(pts()[i]) }
        } else {
            for i in (eIdx...sIdx).reversed() { segment.append(pts()[i]) }
        }
        return segment
    }

    // MARK: - Helpers
    private func loadJSON<T: Decodable>(filename: String, fileExtension: String = "json") throws -> T {
        guard let url = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
            throw NSError(domain: "GTFSMapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing: \(filename).\(fileExtension)"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct AnyCodingKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int?
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }
}
