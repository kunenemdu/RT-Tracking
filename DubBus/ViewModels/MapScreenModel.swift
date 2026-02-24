//
//  MapViewModel.swift
//  DubBus
//
//

import CoreLocation
import MapKit
import SwiftUI
import Combine


final class MapScreenModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    var locationManager: CLLocationManager
    
    // Center the camera on user immediately
    @Published var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 53.2875, longitude: -6.3664), distance: 2000))
    @Published var lastKnownLocation: CLLocation? = nil
    
    override init() {
        self.locationManager = CLLocationManager()
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.locationManager.distanceFilter = 50 // meters
        self.locationManager.pausesLocationUpdatesAutomatically = true
    }
    
    func checkLocationEnabled () {
        print("checking location services")
        if !CLLocationManager.locationServicesEnabled() {
            print("location services off")
        }
    }
    
    func checkLocationAuthorization () {
        print("checking location authorization")
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            print("not determined")
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("restricted/denied")
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            print("authorized - started updates")
        @unknown default:
            break
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }

        // Coalesce updates: only publish if moved more than distanceFilter
        var shouldPublish = true
        if let last = self.lastKnownLocation {
            let minMove = manager.distanceFilter > 0 ? manager.distanceFilter : 100 // default small threshold
            shouldPublish = loc.distance(from: last) >= minMove
        }
        guard shouldPublish else { return }

        DispatchQueue.main.async {
            self.lastKnownLocation = loc
            self.position = .camera(
                MapCamera(centerCoordinate: loc.coordinate, distance: 2000)
            )
        }
    }
}

