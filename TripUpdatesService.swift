import Foundation

struct TripUpdatesFeed: Decodable {
    let entity: [TripUpdateEntity]
}

struct TripUpdateEntity: Decodable {
    let id: String
    let trip_update: TripUpdatePayloadTU
}

struct TripUpdatePayloadTU: Decodable {
    let trip: TripDescriptor
    let stop_time_update: [StopTimeUpdate]
    let vehicle: VehicleDescriptorTU?
    let timestamp: String?
}

struct TripDescriptor: Decodable {
    let trip_id: String
    let start_time: String?
    let start_date: String?
    let schedule_relationship: String?
    let route_id: String?
    let direction_id: Int?
}

struct StopTimeUpdate: Decodable {
    let stop_sequence: Int?
    let arrival: StopTimeEvent?
    let departure: StopTimeEvent?
    let stop_id: String
    let schedule_relationship: String?
}

struct StopTimeEvent: Decodable {
    let delay: Int?
}

struct VehicleDescriptorTU: Decodable {
    let id: String?
}

final class TripUpdatesService {
    private let apiKey: String = ""
    private let endpoint = URL(string: "https://api.nationaltransport.ie/gtfsr/v2/TripUpdates?format=json")!

    func fetchStopToRoutes(completion: @escaping ([String: Set<String>]) -> Void) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("TripUpdatesService: network error:", error)
                completion([:])
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("TripUpdatesService: HTTP status:", http.statusCode)
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    print("TripUpdatesService: body:\n", body)
                }
                completion([:])
                return
            }

            guard let data = data else {
                print("TripUpdatesService: no data")
                completion([:])
                return
            }

            do {
                let decoded = try JSONDecoder().decode(TripUpdatesFeed.self, from: data)
                var map: [String: Set<String>] = [:] // stop_id -> {route_id}
                for e in decoded.entity {
                    let routeId = e.trip_update.trip.route_id
                    guard let route = routeId, !route.isEmpty else { continue }
                    for stu in e.trip_update.stop_time_update {
                        let stopId = stu.stop_id
                        map[stopId, default: []].insert(route)
                    }
                }
                completion(map)
            } catch {
                print("TripUpdatesService: decode error:", error)
                if let body = String(data: data, encoding: .utf8) {
                    print("TripUpdatesService: raw body (first 1KB):\n", String(body.prefix(1024)))
                }
                completion([:])
            }
        }.resume()
    }
}

