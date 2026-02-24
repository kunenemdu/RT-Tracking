//
//  BusViewModel.swift
//  DubBus
//
//


import Foundation
import Combine
import MapKit

class BusViewModel: ObservableObject {
    
    //buses are all loaded at runtime
    @Published var buses: [Bus] = []
    
    @Published var allStops: [BusStop] = []
    private var timer: Timer?
    
    private let service = GTFSRService()
    
    func loadBuses() {
        service.fetchVehiclePositions { [weak self] buses in
            DispatchQueue.main.async {
                self?.buses = buses
            }
        }
    }
    
    func startLiveUpdates() {
        // Only start live updates when a stop is selected
        guard selectedStop != nil else { return }
        // Avoid creating multiple timers
        timer?.invalidate()
        loadBuses()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.loadBuses()
        }
    }
    
    func stopLiveUpdates() {
        timer?.invalidate()
        timer = nil
    }
    
    init() {
    }

    //closest stops to user
    func updateVisibleStops(near userLocation: CLLocation, allLoadedStops: [BusStop]) -> [BusStop] {
        let sorted = allLoadedStops.sorted {
            let loc1 = CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            let loc2 = CLLocation(latitude: $1.latitude, longitude: $1.longitude)
            return loc1.distance(from: userLocation) < loc2.distance(from: userLocation)
        }
        
        // Return only the 10 closest stops to prevent texture lag
        return Array(sorted.prefix(10))
    }
    
    @Published var selectedStop: BusStop?

    func select(stop: BusStop) {
        selectedStop = stop
        
    }
    
    
}

