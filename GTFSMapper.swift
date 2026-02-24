import Foundation

// New struct to hold summarized route information for display/mapping
// Made public as it will be used outside GTFSMapper enum
struct GTFSRouteInfo: Identifiable, Hashable, Decodable {
    let id: String // Corresponds to route_id
    let shortName: String // Corresponds to route_short_name
    let longName: String  // Corresponds to route_long_name

    enum CodingKeys: String, CodingKey {
        case id = "route_id"
        case shortName = "route_short_name"
        case longName = "route_long_name"
    }
}

// New struct to represent the mapped route, conforming to CustomStringConvertible for printing
struct MappedRoute: CustomStringConvertible {
    let routeId: String
    let routeShortName: String
    let routeLongName: String
    // Separate trip IDs and stops for each direction
    let direction0TripId: String?
    let direction0Stops: [GTFSStop]
    let direction1TripId: String?
    let direction1Stops: [GTFSStop]

    var description: String {
        var output = "\n[GTFS] FINAL MAPPING for Route: \(routeShortName) (\(routeLongName))\n"
        output += "- Route ID: \(routeId)\n"

        // Display for Direction 0
        if let tripId0 = direction0TripId {
            output += "- Direction 0 (Trip: \(tripId0)) -> stops (\(direction0Stops.count))\n"
            output += "  Stops for Direction 0:\n"
            for stop in direction0Stops {
                let name = stop.stop_name ?? "(no name)"
                output += "    • stop_id: \(stop.stop_id), name: \(name), lat: \(stop.stop_lat), lon: \(stop.stop_lon)\n"
            }
        } else {
            output += "- Direction 0: No trip found.\n"
        }

        // Display for Direction 1
        if let tripId1 = direction1TripId {
            output += "- Direction 1 (Trip: \(tripId1)) -> stops (\(direction1Stops.count))\n"
            output += "  Stops for Direction 1:\n"
            for stop in direction1Stops {
                let name = stop.stop_name ?? "(no name)"
                output += "    • stop_id: \(stop.stop_id), name: \(name), lat: \(stop.stop_lat), lon: \(stop.stop_lon)\n"
            }
        } else {
            output += "- Direction 1: No trip found.\n"
        }
        return output
    }
}

// Minimal GTFS models for decoding JSON arrays
private struct GTFSRoute: Decodable {
    let route_id: String
    let route_short_name: String
    let route_long_name: String
}

private struct GTFSTrip: Decodable {
    let route_id: String
    let trip_id: String
    let direction_id: Int // This will hold the parsed Int

    enum CodingKeys: String, CodingKey {
        case route_id
        case trip_id
        case direction_id
    }

    // Custom initializer to handle direction_id which might be Int or String
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route_id = try container.decode(String.self, forKey: .route_id)
        trip_id = try container.decode(String.self, forKey: .trip_id)

        // Attempt to decode direction_id as Int directly
        if let intDirectionId = try? container.decode(Int.self, forKey: .direction_id) {
            direction_id = intDirectionId
        } else if let stringDirectionId = try? container.decode(String.self, forKey: .direction_id),
                  let intDirectionId = Int(stringDirectionId) {
            // If that fails, decode as String and try to convert to Int
            direction_id = intDirectionId
        } else {
            // If neither works, throw a decoding error
            let context = DecodingError.Context(codingPath: [CodingKeys.direction_id], debugDescription: "direction_id is neither Int nor a String convertible to Int")
            throw DecodingError.typeMismatch(Int.self, context)
        }
    }
}

// GTFSStopTime struct is no longer needed as stop_times.json is now a dictionary [String: [String]]

// Changed GTFSStop from private to internal (default) so it can be used in MappedRoute
struct GTFSStop: Decodable {
    let stop_id: String
    let stop_name: String?
    let stop_lat: Double // Added latitude property
    let stop_lon: Double // Added longitude property

    enum CodingKeys: String, CodingKey {
        case stop_id
        case stop_name
        case stop_lat // Added to CodingKeys
        case stop_lon // Added to CodingKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Attempt to decode stop_id as String first
        if let stringId = try? container.decode(String.self, forKey: .stop_id) {
            stop_id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .stop_id) {
            // If that fails, decode as Int and convert to String
            stop_id = String(intId)
        } else {
            // Throw decoding error if neither works
            let context = DecodingError.Context(codingPath: [CodingKeys.stop_id], debugDescription: "stop_id is neither String nor Int")
            throw DecodingError.typeMismatch(String.self, context)
        }

        stop_name = try? container.decode(String.self, forKey: .stop_name)
        stop_lat = try container.decode(Double.self, forKey: .stop_lat)
        stop_lon = try container.decode(Double.self, forKey: .stop_lon)
    }
}

/// A small utility to build and print mapping from route -> trips -> stops
enum GTFSMapper {
    // MARK: - Caching
    private static var cachedStops: [GTFSStop]?
    private static var cachedRoutes: [GTFSRoute]?
    private static var cachedTrips: [GTFSTrip]?
    private static var cachedStopTimes: [String: [String]]?
    private static var cachedMappedRoutes: [String: MappedRoute] = [:]
    private static var cachedStopToRoutes: [String: [GTFSRouteInfo]]?

    // Dataset loader helpers with caching
    private static func loadStops() throws -> [GTFSStop] {
        if let s = cachedStops { return s }
        let s: [GTFSStop] = try loadJSON(filename: "stops")
        cachedStops = s
        return s
    }
    private static func loadRoutes() throws -> [GTFSRoute] {
        if let r = cachedRoutes { return r }
        let r: [GTFSRoute] = try loadJSON(filename: "routes")
        cachedRoutes = r
        return r
    }
    private static func loadTrips() throws -> [GTFSTrip] {
        if let t = cachedTrips { return t }
        let t: [GTFSTrip] = try loadJSON(filename: "trips")
        cachedTrips = t
        return t
    }
    private static func loadStopTimes() throws -> [String: [String]] {
        if let st = cachedStopTimes { return st }
        let st: [String: [String]] = try loadJSON(filename: "stop_times")
        cachedStopTimes = st
        return st
    }

    /// Entry point to run the mapping for a specific route id
    /// Returns a `MappedRoute` object if successful, or `nil` if the route is not found or an error occurs.
    static func run(routeId: String) -> MappedRoute? { // Changed return type
        print("[DEBUG][GTFSMapper.run] Starting run for routeId: \(routeId)")

        if let cached = cachedMappedRoutes[routeId] {
            print("[DEBUG][GTFSMapper.run] Returning cached mapped route for \(routeId)")
            return cached
        }

        do {
            // 1) Load all datasets
            print("[DEBUG][GTFSMapper.run] Loading stops.json")
            let stops = try loadStops()
            print("[DEBUG][GTFSMapper.run] Loaded stops.json successfully, count: \(stops.count)")

            print("[DEBUG][GTFSMapper.run] Loading routes.json")
            let routes = try loadRoutes()
            print("[DEBUG][GTFSMapper.run] Loaded routes.json successfully, count: \(routes.count)")

            print("[DEBUG][GTFSMapper.run] Loading trips.json")
            let trips = try loadTrips()
            print("[DEBUG][GTFSMapper.run] Loaded trips.json successfully, count: \(trips.count)")

            print("[DEBUG][GTFSMapper.run] Loading stop_times.json (as dictionary of String to [String])")
            let stopTimes = try loadStopTimes()
            print("[DEBUG][GTFSMapper.run] Loaded stop_times.json successfully, count: \(stopTimes.count) trips")

            // Print some samples for debugging (optional, can be removed)
            print("[GTFS] Loaded counts -> routes: \(routes.count), trips: \(trips.count), stop_times: \(stopTimes.count), stops: \(stops.count)")
            if let firstStopTimeEntry = stopTimes.first {
                print("Sample stop_times entry: Key='\(firstStopTimeEntry.key)', Value=\(firstStopTimeEntry.value.prefix(5))...")
            }
            print(stops.prefix(5))

            // 2) Verify route exists and get its details
            print("[DEBUG][GTFSMapper.run] Verifying existence of route id: \(routeId)")
            guard let route = routes.first(where: { $0.route_id == routeId }) else {
                print("[GTFS][warn] Route id not found: \(routeId)")
                print("[DEBUG][GTFSMapper.run] Exiting early due to missing route")
                return nil // Return nil if route not found
            }
            let routeShortName = route.route_short_name
            let routeLongName = route.route_long_name
            print("[GTFS] Route found: \(routeId) (Short Name: \(routeShortName), Long Name: \(routeLongName))")

            // 3) Find the FIRST trip for each direction for this route
            print("[DEBUG][GTFSMapper.run] Finding first trips for route id: \(routeId) (both directions)")
            
            var direction0TripId: String?
            var direction0StopIdsInOrder: [String] = []
            var direction1TripId: String?
            var direction1StopIdsInOrder: [String] = []
            
            // Attempt to find trip for direction 0
            if let tripForDirection0 = trips.first(where: { $0.route_id == routeId && $0.direction_id == 0 }) {
                direction0TripId = tripForDirection0.trip_id
                print("[GTFS] First trip for route \(routeId), direction 0: \(tripForDirection0.trip_id)")

                if let stopIds = stopTimes[tripForDirection0.trip_id] {
                    direction0StopIdsInOrder = stopIds
                } else {
                    print("[GTFS][warn] No stop_ids found in stop_times.json for trip: \(tripForDirection0.trip_id) (Direction 0)")
                }
            } else {
                print("[GTFS][warn] No trip found for route id: \(routeId), direction 0")
            }

            // Attempt to find trip for direction 1
            if let tripForDirection1 = trips.first(where: { $0.route_id == routeId && $0.direction_id == 1 }) {
                direction1TripId = tripForDirection1.trip_id
                print("[GTFS] First trip for route \(routeId), direction 1: \(tripForDirection1.trip_id)")

                if let stopIds = stopTimes[tripForDirection1.trip_id] {
                    direction1StopIdsInOrder = stopIds
                } else {
                    print("[GTFS][warn] No stop_ids found in stop_times.json for trip: \(tripForDirection1.trip_id) (Direction 1)")
                }
            } else {
                print("[GTFS][warn] No trip found for route id: \(routeId), direction 1")
            }

            // If no trips were found for either direction, then we can't map anything
            guard direction0TripId != nil || direction1TripId != nil else {
                print("[GTFS][warn] No trips found for route id: \(routeId) in either direction.")
                print("[DEBUG][GTFSMapper.run] Exiting early due to no trips found for route in any direction")
                return nil
            }
            
            print("[DEBUG][GTFSMapper.run] Found trips for directions 0: \(direction0TripId ?? "N/A"), 1: \(direction1TripId ?? "N/A")")

            // 4) Lookup stop details for each direction's stops, maintaining order
            print("[DEBUG][GTFSMapper.run] Looking up stop details for collected stop_ids for each direction")
            let stopsById = Dictionary(uniqueKeysWithValues: stops.map { ($0.stop_id, $0) })
            
            var finalDirection0Stops: [GTFSStop] = []
            for sid in direction0StopIdsInOrder {
                if let stop = stopsById[sid] {
                    finalDirection0Stops.append(stop)
                } else {
                    print("[GTFS][warn] stop_id not found in stops.json for Direction 0: \(sid)")
                }
            }

            var finalDirection1Stops: [GTFSStop] = []
            for sid in direction1StopIdsInOrder {
                if let stop = stopsById[sid] {
                    finalDirection1Stops.append(stop)
                } else {
                    print("[GTFS][warn] stop_id not found in stops.json for Direction 1: \(sid)")
                }
            }
            print("[DEBUG][GTFSMapper.run] Completed lookup of stop details for both directions")

            // 5) Build the MappedRoute object and print its description
            let mappedRoute = MappedRoute(
                routeId: routeId,
                routeShortName: routeShortName,
                routeLongName: routeLongName,
                direction0TripId: direction0TripId,
                direction0Stops: finalDirection0Stops,
                direction1TripId: direction1TripId,
                direction1Stops: finalDirection1Stops
            )
            print(mappedRoute) // This prints the summary using the CustomStringConvertible implementation

            cachedMappedRoutes[routeId] = mappedRoute

            print("[DEBUG][GTFSMapper.run] Finished run for routeId: \(routeId)")
            return mappedRoute
        } catch {
            print("[GTFS][error] Operation failed with error: \(error)")
            print("[DEBUG][GTFSMapper.run][error] Caught error in run for routeId: \(routeId)")
            return nil // Return nil on error
        }
    }

    /// Generates a mapping from stop_id to all GTFSRouteInfo objects that serve that stop.
    /// This function is intended to be called once at app launch to pre-compute the mapping.
    static func generateStopToRouteMapping() -> [String: [GTFSRouteInfo]]? {
        print("[DEBUG][GTFSMapper.generateStopToRouteMapping] Starting global mapping generation")

        if let cached = cachedStopToRoutes {
            print("[DEBUG][GTFSMapper.generateStopToRouteMapping] Using cached mapping")
            return cached
        }

        do {
            let routes = try loadRoutes()
            let trips = try loadTrips()
            let stopTimes = try loadStopTimes()

            var stopToRoutesMap: [String: Set<GTFSRouteInfo>] = [:] // Using a Set to ensure unique routes per stop

            // Pre-process routes for easy lookup
            let routeInfoById = Dictionary(uniqueKeysWithValues: routes.map {
                ($0.route_id, GTFSRouteInfo(id: $0.route_id, shortName: $0.route_short_name, longName: $0.route_long_name))
            })

            // Iterate through all trips to build the stop-to-route mapping
            for trip in trips {
                if let routeInfo = routeInfoById[trip.route_id] {
                    if let stopIdsForTrip = stopTimes[trip.trip_id] {
                        for stopId in stopIdsForTrip {
                            stopToRoutesMap[stopId, default: []].insert(routeInfo)
                        }
                    }
                }
            }

            // Convert Sets to Arrays for the final return, sorted by shortName for consistent output
            let finalMap = stopToRoutesMap.mapValues { Array($0).sorted { $0.shortName < $1.shortName } }
            
            cachedStopToRoutes = finalMap
            print("[DEBUG][GTFSMapper.generateStopToRouteMapping] Finished global mapping generation. Mapped stops: \(finalMap.count)")
            return finalMap
        } catch {
            print("[GTFS][error] Failed to generate stop-to-route mapping: \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    private static func loadJSON<T: Decodable>(filename: String) throws -> T {
        print("[DEBUG][loadJSON] Start loading JSON file: \(filename).json")
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: filename, withExtension: "json") else {
            let available = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
                .map { $0.lastPathComponent }
                .joined(separator: ", ")
            print("[DEBUG][loadJSON][error] Missing resource: \(filename).json")
            throw NSError(
                domain: "GTFSMapper",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing resource: \(filename).json in bundle. Available JSONs: [\(available)]"]
            )
        }
        print("[DEBUG][loadJSON] Found file URL: \(url.lastPathComponent)")
        let data = try Data(contentsOf: url)
        print("[DEBUG][loadJSON] Read data of length \(data.count) bytes")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        print("[DEBUG][loadJSON] Starting decode of \(filename).json")
        let decoded = try decoder.decode(T.self, from: data)
        print("[DEBUG][loadJSON] Finished decode of \(filename).json")
        print("[DEBUG][loadJSON] Finished loading JSON file: \(filename).json")
        return decoded
    }
}

