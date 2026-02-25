//
//  Bus.swift
//  DubBus
//
//

import Foundation
import CoreLocation
import SwiftData

struct Bus: Identifiable, Equatable {
    let id: String           // The "47" from vehicle.id
    let tripId: String?      // The "5240_1144"
    let routeId: String      // The "5240_119662"
    let coordinate: CLLocationCoordinate2D
    
    // Optional: Add info from your routes.json later
    var routeName: String?
    var color: String?

    static func == (lhs: Bus, rhs: Bus) -> Bool {
        lhs.id == rhs.id &&
        lhs.tripId == rhs.tripId &&
        lhs.routeId == rhs.routeId &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.routeName == rhs.routeName &&
        lhs.color == rhs.color
    }
}
