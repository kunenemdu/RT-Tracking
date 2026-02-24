//
//  GTFSRResponse.swift
//  DubBus
//
//


import Foundation

struct GTFSRResponse: Codable {
    let entity: [FeedEntity]
}

struct FeedEntity: Codable {
    let id: String
    let vehicle: Vehicle?
}

struct Vehicle: Codable {
    let trip: Trip?
    let position: Position?
    let timestamp: String?
    let vehicle: VehicleDescriptor? // Matches the nested "vehicle": { "id": "47" }
}

struct Trip: Codable {
    let tripId: String?
    let routeId: String?
    let directionId: Int?

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case routeId = "route_id"
        case directionId = "direction_id"
    }
}

struct VehicleDescriptor: Codable {
    let id: String?
}

struct Position: Codable {
    let latitude: Double?
    let longitude: Double?
    let bearing: Double?

    enum CodingKeys: String, CodingKey {
        case latitude = "latitude"
        case longitude = "longitude"
        case bearing = "bearing"
    }
}
