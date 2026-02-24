# 🚌 Real-Time Bus Tracker

A real-time iOS bus tracking app built with SwiftUI and MapKit, centered around Springfield, Tallaght.

The app integrates with the National Transport Authority (NTA) GTFS-Realtime API to display live vehicle positions directly on the map.

---

## 📍 Features

- 🗺️ Live Map View (MapKit)
- 🚌 Real-time Bus Locations (GTFS-Realtime Vehicles feed)
- 📡 Live Updates from NTA API
- 🎯 Default map region centered on Springfield, Tallaght
- 🧭 CLLocation integration
- 🧩 Clean MVVM architecture

---

## 🛠 Tech Stack

- Swift
- SwiftUI
- MapKit
- CoreLocation
- URLSession
- NTA GTFS-Realtime API (JSON format)

---

## 🌍 API Integration

This app uses the NTA GTFS-Realtime Vehicles endpoint:
https://api.nationaltransport.ie/gtfsr/v2/Vehicles?format=json


Data source:
National Transport Authority (Ireland)

Feed type used:
- ✅ Vehicles (for live positions)
- ⛔ TripUpdates (not currently used)
- ⛔ Alerts (not currently used)

---

## 🏗 Architecture

The project follows MVVM:

### BusViewModel
- Handles API calls
- Decodes GTFSR JSON
- Publishes live bus array
- Manages polling with `startLiveUpdates()`

### GTFSRService
- Performs network requests
- Returns decoded feed data

### MapView
- Displays buses as annotations
- Uses custom bus icons
- Observes published bus updates

---

## 📡 Live Updates Flow

1. `startLiveUpdates()` is called on launch
2. `loadBuses()` fetches vehicle data
3. JSON is decoded into model structs
4. Bus coordinates are extracted
5. Map annotations update automatically via @Published


---

## 📌 Default Map Location

Centered on:
Springfield, Tallaght, Dublin

Coordinates:
Approximate region around South Dublin.

---

## 🚀 Future Improvements

- Route filtering
- Individual Vehicle identification
- Bus tap → route info popup
- ETA predictions (TripUpdates integration)
- Stop-level tracking
- Background refresh
- Push notifications for selected routes
- Performance optimization with diff updates
- Clustering when zoomed out

---

## ⚠️ Notes

- Requires valid NTA API key
- API key should not be hardcoded in production
- Use secure storage or backend proxy for release builds

---

## 🧪 Development

To run:

1. Open project in Xcode
2. Insert your NTA API key in `GTFSRService`
3. Clean build folder (Shift + Cmd + K)
4. Run on simulator or device

---

## 📄 License

For educational and development purposes.

Data © National Transport Authority Ireland.
