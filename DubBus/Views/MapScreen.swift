//
//  MapScreen.swift
//  DubBus
//
//

import SwiftUI
import SwiftData
import MapKit

struct MapScreen: View {

    @State private var showStopSheet = false
    @StateObject private var viewModel = BusViewModel()
    @StateObject private var stopRoutesVM = StopRoutesViewModel()
    @StateObject private var mapScreenModel = MapScreenModel()
    @State var searchInput = ""
    @State private var filteredStops: [BusStop] = [] // NEW: State for search results
    
    //zoom in on user then load map
    @State private var position: MapCameraPosition = .automatic
    
    @State var sheetPresented: Bool = false
    @State var nearbyButtonVisibility: Bool = true
    @Query var allStops: [BusStop]
    @State private var nearbyStopsState: [BusStop] = []
    @State private var recomputeToken = UUID()
    @State private var hasCenteredOnUser = false
    @State private var lastRecomputeLocation: CLLocation? = nil
    private let recomputeThreshold: CLLocationDistance = 100
    @State private var selectedRoute: GTFSRouteInfo? = nil
    
    @State private var searchWorkItem: DispatchWorkItem? = nil
    @State private var searchIndex: [StopSearchEntry] = []
    @State private var ignoreNextMapTapClose = false

    @State private var selectedRoutePolyline: MKPolyline? = nil // State to hold the polyline for the selected route
    
    // Fallback location (Tallaght Cross) used until we have a user fix
    let fallbackLocation = CLLocation(latitude: 53.2875, longitude: -6.3664)
    
    
    //main map
    var body: some View {
        Map (position: $position) {
            UserAnnotation()
            // 1. Display Bus Stops using Markers (Standard Look)
            ForEach(nearbyStopsState) { stop in
                Annotation(String(stop.stopCode), coordinate: stop.coordinate) {
                    VStack {
                        Image(systemName: "bus")
                            .padding(8)
                            .background(Color.yellow)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black, lineWidth: 2))
                            .onTapGesture {
                                // Mark to ignore the next map tap close since this is an annotation tap
                                ignoreNextMapTapClose = true
                                // on selection:
                                viewModel.select(stop: stop)
                                selectedRoute = nil
                                selectedRoutePolyline = nil // Clear polyline when a new stop is selected directly on map
                                sheetPresented = false
                                showStopSheet = true
                                print("selected stop: \(stop.stopCode)")
                            }
                    }
                }
            }
            
            // Display the selected bus route polyline
            if let polyline = selectedRoutePolyline {
                MapPolyline(polyline)
                    .stroke(Color.blue, lineWidth: 5)
            }

            // NEW: Display real-time bus locations for the selected route
            if let selectedRoute = selectedRoute {
                ForEach(viewModel.buses.filter { $0.routeId == selectedRoute.id }) { bus in
                    Annotation(bus.id, coordinate: bus.coordinate) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 32, height: 32)
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                Image(systemName: "bus.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Text(selectedRoute.shortName)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            if ignoreNextMapTapClose {
                ignoreNextMapTapClose = false
                return
            }
            // Close all sheets and clear search when tapping on the map
            showStopSheet = false
            sheetPresented = false
            searchInput = ""
            filteredStops = []
            selectedRoute = nil
            selectedRoutePolyline = nil // Clear polyline on map tap
        })
        .overlay(alignment: .top) {
            VStack {
                // NEW: Use SearchOverlay for search functionality
                SearchOverlay(
                    searchText: $searchInput,
                    filteredStops: filteredStops,
                    onSelect: { selectedStop in
                        // Action when a stop is selected from the dropdown
                        self.searchInput = "" // Clear search input
                        self.filteredStops = [] // Clear filtered results to dismiss the overlay
                        
                        // Pan the camera to the selected stop's coordinate
                        self.position = .camera(MapCamera(centerCoordinate: selectedStop.coordinate, distance: 150))
                        
                        // Select the stop in the view model and show the stop sheet
                        viewModel.select(stop: selectedStop)
                        selectedRoute = nil
                        selectedRoutePolyline = nil // Clear polyline when a new stop is selected from search
                        showStopSheet = true
                        sheetPresented = false // Ensure the nearby stops sheet is dismissed
                    }
                )
                
                Spacer()
                // Button only visible if sheet is NOT showing AND search is not active
                if !sheetPresented && searchInput.isEmpty { // Show a capsule button when the sheet is closed
                    Button {
                        sheetPresented = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.headline)
                            Text("Nearby Stops")
                                .font(.headline.weight(.semibold))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .transition(.opacity.combined(with: .scale))
                }
                
            }
        }
        .onAppear {
            // Ensure we have permission and start getting user location immediately
            mapScreenModel.checkLocationEnabled()
            if let userLoc = mapScreenModel.lastKnownLocation {
                recomputeNearbyStops(for: userLoc)
                lastRecomputeLocation = userLoc
            } else {
                // Center the camera to fallback for initial visual context, but do not recompute yet
                position = .camera(MapCamera(centerCoordinate: fallbackLocation.coordinate, distance: 2000))
            }
            stopRoutesVM.loadStaticStopRoutes()
            searchIndex = allStops.map { StopSearchEntry(stop: $0, code: String($0.stopCode), nameLower: $0.name.lowercased()) }
        }
        .onDisappear {
            viewModel.stopLiveUpdates()
        }
        .onChange(of: mapScreenModel.lastKnownLocation) { newLoc in
            print("location update!")
            guard let loc = newLoc else { return }

            // Center on user once, regardless of recompute threshold
            if !hasCenteredOnUser {
                position = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: 2000))
                hasCenteredOnUser = true
            }

            // Only recompute if moved more than the threshold from the last recompute location
            if let last = lastRecomputeLocation {
                let distance = loc.distance(from: last)
                print("distance since last recompute: \(distance) m")
                guard distance >= recomputeThreshold else { return }
            }

            lastRecomputeLocation = loc
            recomputeNearbyStops(for: loc)
        }
        .onChange(of: allStops.count) { _ in
            print("allstops changed!")
            if let loc = mapScreenModel.lastKnownLocation {
                recomputeNearbyStops(for: loc)
            }
            // Rebuild the search index when the dataset changes
            searchIndex = allStops.map { StopSearchEntry(stop: $0, code: String($0.stopCode), nameLower: $0.name.lowercased()) }
        }
        .onChange(of: searchInput) { newValue in
            // Cancel any pending search work
            searchWorkItem?.cancel()

            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                filteredStops = []
                return
            }

            // Debounce to avoid filtering on every keystroke
            let work = DispatchWorkItem {
                let qLower = trimmed.lowercased()
                let indexSnapshot = self.searchIndex
                var results: [BusStop] = []
                results.reserveCapacity(50)
                var seenCodes = Set<String>()

                func appendIfNew(_ entry: StopSearchEntry) -> Bool {
                    if seenCodes.insert(entry.code).inserted {
                        results.append(entry.stop)
                        return results.count >= 50
                    }
                    return false
                }

                // 1) Code prefix matches
                for entry in indexSnapshot {
                    if entry.code.hasPrefix(trimmed) {
                        if appendIfNew(entry) { break }
                    }
                }
                // 2) Name prefix matches
                if results.count < 50 {
                    for entry in indexSnapshot {
                        if entry.nameLower.hasPrefix(qLower) {
                            if appendIfNew(entry) { break }
                        }
                    }
                }
                // 3) Code contains matches
                if results.count < 50 {
                    for entry in indexSnapshot {
                        if entry.code.contains(trimmed) {
                            if appendIfNew(entry) { break }
                        }
                    }
                }
                // 4) Name contains matches
                if results.count < 50 {
                    for entry in indexSnapshot {
                        if entry.nameLower.contains(qLower) {
                            if appendIfNew(entry) { break }
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.filteredStops = results
                }
            }
            searchWorkItem = work
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        .onChange(of: selectedRoute) { newRoute in // React to selectedRoute changes
            if let route = newRoute {
                Task {
                    // Corrected to use the shared instance of the GTFSMapper actor
                    selectedRoutePolyline = await GTFSMapper.shared.loadSnappedRoutePolyline(forRouteId: route.id)
                    
                    if let polyline = selectedRoutePolyline {
                        print("Loaded snapped polyline for route \(route.id). Adjusting map camera.")
                        // Adjust map camera to fit the polyline
                        let mapRect = polyline.boundingMapRect
                        let paddedRect = mapRect.insetBy(dx: -mapRect.width * 0.2, dy: -mapRect.height * 0.2) // 20% padding
                        withAnimation {
                            position = .rect(paddedRect)
                        }
                    } else {
                        print("Failed to load snapped polyline for route \(route.id)")
                    }
                }
            } else {
                selectedRoutePolyline = nil // Clear polyline if no route is selected
                print("Selected route cleared, polyline removed.")
            }
        }
        // NEW: Toggle live updates when the stop sheet is shown/hidden
        .onChange(of: showStopSheet) { isShowing in
            if isShowing {
                viewModel.startLiveUpdates()
            } else {
                viewModel.stopLiveUpdates()
            }
        }
        
        //nearby stops bottom sheet
        .sheet(isPresented: $sheetPresented) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Nearby Stops")
                        .font(.headline)
                    Spacer()
                    Button {
                        sheetPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(nearbyStopsState) { stop in
                            Button {
                                // Open stop details
                                viewModel.select(stop: stop)
                                selectedRoute = nil
                                selectedRoutePolyline = nil // Clear polyline when a new stop is selected from nearby sheet
                                sheetPresented = false
                                showStopSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(.thinMaterial)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "bus.fill")
                                            .foregroundStyle(.green)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stop.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text("Stop \(String(stop.stopCode))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
            .presentationDetents([.fraction(0.30), .medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
            .presentationBackgroundInteraction(.enabled)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sheetPresented)
        }

        //selected stop sheet:
        .sheet(isPresented: $showStopSheet, onDismiss: { selectedRoute = nil; selectedRoutePolyline = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                if let stop = viewModel.selectedStop {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stop.name)
                                .font(.title3).bold()
                                .lineLimit(2)
                            Text("Stop \(String(stop.stopCode))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            selectedRoute = nil
                            selectedRoutePolyline = nil // Clear polyline when sheet is closed
                            showStopSheet = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    let routes = stopRoutesVM.routesFor(stop: stop)
                    if routes.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading routes...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Routes")
                            .font(.subheadline).bold()
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                            ForEach(routes) { route in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        // Toggle selected route
                                        if selectedRoute?.id == route.id {
                                            selectedRoute = nil
                                        } else {
                                            selectedRoute = route
                                        }
                                    }
                                    print("Toggled route selection for:", route.shortName, route.id)
                                } label: {
                                    RoutePill(title: route.shortName,
                                              isSelected: selectedRoute?.id == route.id,
                                              baseColor: colorForRoute(route.shortName))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .presentationDetents([.fraction(0.35), .medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
            .presentationBackgroundInteraction(.enabled)
        }
        
    }
    
    private func recomputeNearbyStops(for location: CLLocation) {
        let stops = allStops
        let token = UUID()
        recomputeToken = token
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
            if self.recomputeToken != token { return }
            let sorted = stops.sorted {
                let loc1 = CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                let loc2 = CLLocation(latitude: $1.latitude, longitude: $1.longitude)
                return loc1.distance(from: location) < loc2.distance(from: location)
            }
            let top10 = Array(sorted.prefix(10))
            DispatchQueue.main.async {
                if self.recomputeToken != token { return }
                self.nearbyStopsState = top10
            }
        }
    }
    
}

private struct StopSearchEntry {
    let stop: BusStop
    let code: String
    let nameLower: String
}

private func colorForRoute(_ key: String) -> Color {
    var hasher = Hasher()
    hasher.combine(key)
    let hash = hasher.finalize()
    let positive = abs(hash)
    let hue = Double(positive % 256) / 255.0
    return Color(hue: hue, saturation: 0.65, brightness: 0.85)
}

private struct RoutePill: View {
    let title: String
    let isSelected: Bool
    let baseColor: Color

    var body: some View {
        let gradient = LinearGradient(colors: [baseColor.opacity(0.95), baseColor.opacity(0.75)],
                                      startPoint: .topLeading,
                                      endPoint: .bottomTrailing)
        Text(title)
            .font(.headline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(gradient)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.9 : 0.25), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: baseColor.opacity(0.25), radius: 8, x: 0, y: 4)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}

struct MapScreen_Previews: PreviewProvider {
    static var previews: some View {
        MapScreen()
    }
}

