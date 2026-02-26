# DubBus — Live Bus Map & Stop Finder for Tallaght, Dublin (SwiftUI + SwiftData)

DubBus is an iOS app that helps you find nearby bus stops in Tallaght, Dublin, browse routes serving a stop, and view live buses on a map. It uses MapKit for the map experience and SwiftData to persist a local catalog of stops. The app supports searching by stop code or name, viewing route polylines, and following an individual bus as it moves.

- iOS 17+
- SwiftUI, MapKit, CoreLocation
- SwiftData for local persistence


## Table of Contents
- Overview
- Features
- Screens & Interactions
- Screenshots
- Getting Started
- Architecture
- Key Components
- Data & APIs
- Data Sources (Dublin)
- Privacy & Permissions
- Troubleshooting
- Roadmap
- Contributing
- License
- Acknowledgments


## Overview
DubBus centers around a single map screen where you can:
- See your location and the nearest stops
- Search by stop code or stop name
- Select a stop to view routes and live tracking
- Pick a route to show its polyline and live buses
- Follow a bus and keep the camera centered on it

Static stop data is bundled with the app (stops.json) and seeded into a SwiftData store on first launch. Live data (buses and route shapes) are provided by view models; the exact data providers are decoupled from the UI so you can adapt them to your own feed.

Default region: Tallaght, Dublin (Ireland). The map’s initial fallback location is set to 53.2875, -6.3664 (Tallaght). You can change this in MapScreen.swift.

```swift:MapScreen.swift
let fallbackLocation = CLLocation(latitude: 53.2875, longitude: -6.3664)
```


## Features
• Nearby stops list and quick access from the map
• Search overlay with fast, debounced matching by stop code and name
• Stop details sheet with two tabs: Routes and Tracking
• Route polyline rendering when a route is selected
• Live bus annotations filtered by selected route
• Follow/unfollow a bus to keep the map centered on it
• Robust stop seeding from JSON with flexible decoding of GTFS-like fields

## Screens & Interactions
• Map screen: user location, nearby stop pins, bus icons, and route polyline
• Search overlay: type a stop code or name; tap a result to jump the camera
• Nearby Stops sheet: a quick list of stops near your current location
• Stop Details sheet: shows a header (stop name/code), a segmented control (Routes / Tracking), route chips, and live bus state

## Screenshots
Add your screenshots and GIFs to a Docs/ folder in the repo and ensure these file names exist, or update the paths below accordingly.

Map centered on Tallaght
Stop details & tracking
Demo of selecting a stop, route, and following a bus

## Getting Started

Requirements
• Xcode 15 or later
• iOS 17 or later

Build & Run
1. Clone the repository.
2. Open the Xcode project/workspace.
3. Build and run on a device or simulator.
4. On first launch, the app seeds the local database from stops.json in the app bundle.

Permissions
When prompted, grant Location permission so the app can show nearby stops and center the map on your position.

Architecture
The app follows a lightweight MVVM approach with SwiftUI views, model types persisted by SwiftData, and view models responsible for fetching/transforming data.

• UI: SwiftUI views (MapScreen, overlays, sheets)
• State & Logic: View models (e.g., BusViewModel, StopRoutesViewModel, MapScreenModel)
• Persistence: SwiftData with a single model type (BusStop)
• Mapping: MapKit for annotations, camera control, and polylines

High-level flow:
• On app launch, DubBusApp sets up a ModelContainer for SwiftData and triggers stop seeding via DataHandler.
• MapScreen queries stops with @Query, manages user location updates, and coordinates UI state (selected stop, selected route, following bus).
• When a route is selected, a polyline is loaded and the camera adjusts to fit it.
• Live buses are filtered by the selected route; tapping a bus enables Follow mode.

Key Components

App Entry: DubBusApp
Initializes SwiftData and injects the model container into the scene. It also seeds the database on first run and gracefully falls back to an in-memory store if a schema mismatch occurs (useful during development).


## Stop Model: BusStop
A SwiftData @Model that stores stop code, name, coordinates, and a GTFS stop ID. A computed coordinate property returns a CLLocationCoordinate2D for MapKit.

```
@Model
class BusStop: Identifiable {
    @Attribute(.unique) var stopCode: Int
    var name: String
    var latitude: Double
    var longitude: Double
    var gtfsStopId: String

    var id: Int { stopCode }

    enum CodingKeys: String, CodingKey {
        case stopCode = "stop_code"
        case name = "stop_name"
        case latitude = "stop_lat"
        case longitude = "stop_lon"
        case gtfsStopId = "stop_id"
    }
    
    // Standard init required for SwiftData @Model
    init(stopCode: Int, name: String, latitude: Double, longitude: Double, gtfsStopId: String) {
        self.stopCode = stopCode
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.gtfsStopId = gtfsStopId
    }
    
    @Transient
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
```

## Data Seeding: DataHandler
Loads stops.json from the app bundle and inserts rows into SwiftData. The decoding is robust to JSON where stop_id or stop_code might be strings or numbers.

```
@MainActor
class DataHandler {
    static func seedStopsIfEmpty(context: ModelContext) {
        // Check if database already has stops
        let descriptor = FetchDescriptor<BusStop>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }
        print("checking for stops...")

        if count > 0 { return } else {
            print("no stops, seeding...")
            // 1. Locate JSON
            guard let url = Bundle.main.url(forResource: "stops", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return } ...
```

## Main UI: MapScreen
The core screen that hosts the map, overlays, and sheets. It manages:
• User location and nearby stop computation
• Search input and debounced indexing for fast filtering
• Stop selection, route selection, and bus following
• Route polyline loading and camera fitting

Key patterns inside MapScreen:
• @Query var allStops: [BusStop] to read stops from SwiftData
• Local index (StopSearchEntry) to speed up search
• Debounce via DispatchWorkItem to avoid blocking the main thread
• Camera updates using MapCameraPosition and MapCamera
• Live buses filtered by selected route



## View Models (overview)
• BusViewModel: Manages selected stop, live bus updates, and bus list. Starts/stops live updates when the stop sheet is shown/hidden.
• StopRoutesViewModel: Provides routes serving a stop and loads static route metadata.
• MapScreenModel: Handles CoreLocation permissions and exposes lastKnownLocation for the map.

Note: Implementations of these models determine your data sources (e.g., GTFS static data, realtime APIs). Adjust them to your needs.



## Data & APIs

Static Data: stops.json
A bundled JSON file containing stops with GTFS-like fields. The app seeds this into SwiftData on first launch. By default, the bundled dataset covers the Tallaght area of Dublin, Ireland.

To update or replace stops:
• Replace stops.json in the bundle with your city’s stops
• Ensure the JSON keys match the expected names (stop_id, stop_code, stop_name, stop_lat, stop_lon)
• Run the app; seeding happens automatically when the store is empty

Example stops.json snippet
The seeding logic accepts stop_id and stop_code as either strings or numbers, and normalizes them internally.

```[
  {
    "stop_id": "8220DB000001",
    "stop_code": 1234,
    "stop_name": "Tallaght (Square)",
    "stop_lat": 53.2875,
    "stop_lon": -6.3664
  },
  {
    "stop_id": 5678,
    "stop_code": "5678",
    "stop_name": "Tallaght Hospital",
    "stop_lat": 53.2891,
    "stop_lon": -6.3689
  }
]
```


## Customize the default region
To adapt the app to another city or region:
• Replace stops.json with your city’s stops (GTFS), keeping the expected keys.
• Update the fallback location in MapScreen.swift (see snippet above) to center the map appropriately on first launch.
• Ensure your route shape provider (e.g., GTFSMapper) and live bus data source are configured for your region.

## Routes & Polylines
When a route is selected, GTFSMapper.shared.loadSnappedRoutePolyline(forRouteId:) is used to fetch a polyline. The map then fits the polyline with some padding. Provide your own implementation/data for route shapes in GTFSMapper.

## Live Buses
The BusViewModel filters live buses by routeId and publishes updates. The transport mechanism (polling, websockets, etc.) is up to your implementation.

## Data Sources (Dublin)
This project focuses on the Tallaght area of Dublin, Ireland. To power routes and live buses, you can integrate with Dublin/Transport for Ireland (TFI) data sources:

• Static data (GTFS): Stops, routes, trips, and shapes. Convert or pre-process the GTFS stops.txt (and optionally shapes/route files) into the stops.json format used by this app.
• Realtime data (GTFS-RT or vendor APIs): Vehicle Positions and Trip Updates for live bus locations. Your implementation can poll or subscribe and feed updates into BusViewModel.

## Recommendations:
• Review the terms of use and attribution requirements for TFI/Dublin Bus datasets and comply with their licenses.
• Store API keys and endpoint URLs outside source control (e.g., Info.plist entries or a local configuration file) and inject them at runtime.
• Implement your route shape provider (e.g., GTFSMapper) to return MKPolyline for a given route ID.
• If your live feed uses route short names differently, provide a mapping layer so bus annotations can display meaningful labels.

Note: This repository does not bundle proprietary feeds. You are responsible for obtaining access to the relevant open data and for adhering to all usage policies.

## Privacy & Permissions
• Location: Used to show your position and compute nearby stops. The app requests “When In Use” authorization. Add a meaningful NSLocationWhenInUseUsageDescription to your Info.plist.
• Networking: If you enable live data, the app may perform network requests to your realtime provider.
• Local Storage: Stop data is stored locally using SwiftData. During development, schema mismatches fall back to an in-memory store.

## Troubleshooting
• No stops appear:
   • Confirm stops.json exists in the app bundle and is valid JSON.
   • Delete the app from the simulator/device to force reseeding on next launch.
• Location is not centering:
   • Ensure Location permissions are granted in Settings.
   • Simulators need a custom location route or a fixed location.
• Schema mismatch warnings:
   • During development, the app falls back to in-memory storage. If you need persistent changes, reset the store or migrate the schema.
• Route line not showing:
   • Verify your GTFSMapper returns a valid MKPolyline for the selected route ID.

## Roadmap
• Favorites: Save preferred stops and routes
• Alerts: Service alerts and disruptions
• Offline: Cache route shapes and last-known vehicle positions
• Filters: Route and direction filters on the map
• Widgets & Live Activities
• Accessibility improvements and VoiceOver labels for map annotations

## License
This project is licensed under the MIT License. See the LICENSE file for details. If no LICENSE is present, consider adding one before distributing.
Acknowledgments
• Apple frameworks: SwiftUI, MapKit, CoreLocation, SwiftData
• GTFS standards for transit data (for shaping stop and route data)
• Dublin area transit community for inspiration
• Thanks to the open transit developer community for inspiration and best practices
