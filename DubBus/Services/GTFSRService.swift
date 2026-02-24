//
//  GTFSRService.swift
//  DubBus
//
//


import Foundation
import CoreLocation

class GTFSRService {
    
    private let apiKey = "9c465a3e3f8c41cea3aeaff16573107e"
    
    func fetchVehiclePositions(completion: @escaping ([Bus]) -> Void) {
        print("GTFSRService: fetching vehicle positions")
        
        if apiKey.isEmpty {
            print("GTFSRService: WARNING - API key is empty. Set `apiKey` to your NTA key.")
        }
        
        guard let url = URL(string: "https://api.nationaltransport.ie/gtfsr/v2/Vehicles?format=json") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("GTFSRService: network error:", error)
                completion([])
                return
            }

            if let http = response as? HTTPURLResponse {
                print("GTFSRService: HTTP status:", http.statusCode)
                if !(200...299).contains(http.statusCode) {
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        print("GTFSRService: response body:\n", body)
                    }
                }
            }

            guard let data = data else {
                print("GTFSRService: no data returned")
                completion([])
                return
            }

            do {
                let decoded = try JSONDecoder().decode(GTFSRResponse.self, from: data)
                print("GTFSRService: entities count:", decoded.entity.count)

                let buses: [Bus] = decoded.entity.compactMap { entity in
                    guard let veh = entity.vehicle else {
                        // print("Entity has no vehicle:", entity.id)
                        return nil
                    }
                    guard let pos = veh.position, let lat = pos.latitude, let lon = pos.longitude else {
                        // print("Vehicle missing position/coords:", entity.id)
                        return nil
                    }

                    let id = veh.vehicle?.id ?? entity.id
                    let tripId = veh.trip?.tripId
                    let routeId = veh.trip?.routeId ?? "N/A"

                    return Bus(
                        id: id,
                        tripId: tripId,
                        routeId: routeId,
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    )
                }

                print("GTFSRService: parsed buses:", buses.count)
                if buses.isEmpty {
                    // Extra diagnostics to understand drop-offs
                    let sample = decoded.entity.prefix(10)
                    for e in sample {
                        let hasVeh = e.vehicle != nil
                        let hasPos = e.vehicle?.position != nil
                        let lat = e.vehicle?.position?.latitude
                        let lon = e.vehicle?.position?.longitude
                        let trip = e.vehicle?.trip?.tripId
                        let route = e.vehicle?.trip?.routeId
                        print("Sample entity id=\(e.id) vehicle=\(hasVeh) position=\(hasPos) lat=\(String(describing: lat)) lon=\(String(describing: lon)) trip=\(String(describing: trip)) route=\(String(describing: route))")
                    }
                }

                completion(buses)
            } catch {
                print("GTFSRService: JSON decode error:", error)
                if let body = String(data: data, encoding: .utf8) {
                    print("GTFSRService: raw body (first 1KB):\n", String(body.prefix(1024)))
                }
                completion([])
            }
        }.resume()
    }
    
//    func fetchVehiclePositions1() async throws -> [Bus] {
//        let url = URL(string: "https://api.nationaltransport.ie/gtfsr/v2/Vehicles?format=json")!
//        let (data, _) = try await URLSession.shared.data(from: url)
//        let result = try JSONDecoder().decode(GTFSRResponse.self, from: data)
//        let buses: [Bus] = result.entity.compactMap { entity in
//            guard let veh = entity.vehicle,
//                  let pos = veh.position,
//                  let lat = pos.latitude,
//                  let lon = pos.longitude else { return nil }
//            let id = veh.vehicle?.id ?? entity.id
//            let tripId = veh.trip?.tripId
//            let routeId = veh.trip?.routeId ?? "N/A"
//            return Bus(id: id, tripId: tripId, routeId: routeId, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
//        }
//        return buses
//    }
}

