import CoreLocation
import Combine
import Foundation

/// Where to ask for weather (decision 059).
///
/// Two sources, in order: the Mac's own location via CoreLocation, and — when
/// that is off, denied, or simply hasn't produced a fix — a city the user
/// typed in Settings ▸ Weather, geocoded once through Open-Meteo's free
/// geocoder and cached. Either can be missing; both missing means no weather,
/// and the feature quietly shows nothing (Agent Guideline #3).
///
/// Accuracy is deliberately **reduced**: `kCLLocationAccuracyReduced` gives a
/// coarse, city-scale fix, which is all a weather lookup needs and the least
/// the user has to hand over (Agent Guideline #5). It also means macOS shows
/// the "approximate location" prompt rather than the precise one.
///
/// The coordinate never leaves this process except as the two rounded numbers
/// in the Open-Meteo query, and is never logged.
@MainActor
final class LocationService: NSObject, ObservableObject {
    /// The place weather should be fetched for, whichever source produced it.
    @Published private(set) var place: WeatherPlace?
    /// Live CoreLocation authorization, for the Settings pane and the hello
    /// screen's setup row.
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// Set when a typed city could not be resolved, for Settings to show.
    @Published private(set) var cityLookupFailure: String?
    @Published private(set) var isResolvingCity = false

    private let prefs: Preferences
    private let manager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false
    private var cityTask: Task<Void, Never>?
    /// The last fix CoreLocation gave us, kept so that switching *off* "use my
    /// location" and back on doesn't have to wait for a new fix.
    private var devicePlace: WeatherPlace?

    init(prefs: Preferences) {
        self.prefs = prefs
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        // City-scale is the whole point; a 3km filter stops a walk around the
        // block from spending a geocode and a weather request.
        manager.distanceFilter = 3_000
        authorization = manager.authorizationStatus

        prefs.$weatherUseLocation
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.isRunning else { return }
                self.resolve()
            }
            .store(in: &cancellables)

        prefs.$weatherCity
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] city in
                guard let self, self.isRunning else { return }
                self.lookUpCity(city)
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // A cached city from a previous run is a usable place immediately, so
        // the first weather fetch doesn't have to wait on a location fix.
        if let cached = prefs.cachedCityPlace {
            place = cached
        }
        if prefs.weatherUseLocation {
            requestAuthorizationIfNeeded()
        } else if prefs.cachedCityPlace == nil, !prefs.weatherCity.isEmpty {
            lookUpCity(prefs.weatherCity)
        }
        resolve()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        cityTask?.cancel()
        cityTask = nil
    }

    /// Ask for location access. Safe to call repeatedly — CoreLocation only
    /// shows the prompt while the status is `.notDetermined`, and a
    /// denied/restricted status just falls through to the city fallback.
    func requestAuthorizationIfNeeded() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status.grantsLocation {
            manager.startUpdatingLocation()
        }
    }

    /// Pick the best available place: the device fix when the user wants it
    /// and we have one, otherwise the cached city.
    private func resolve() {
        if prefs.weatherUseLocation {
            requestAuthorizationIfNeeded()
            if let devicePlace {
                place = devicePlace
                return
            }
        } else {
            manager.stopUpdatingLocation()
        }
        place = prefs.cachedCityPlace
    }

    // MARK: Typed city

    /// Resolve a typed city to coordinates through Open-Meteo's geocoder —
    /// the same host the weather comes from, also key-free. `CLGeocoder` would
    /// work too, but it is rate-limited per process and refuses outright while
    /// Location Services is off, which is exactly the case this exists for.
    private func lookUpCity(_ city: String) {
        cityTask?.cancel()
        let query = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            cityLookupFailure = nil
            isResolvingCity = false
            prefs.cachedCityPlace = nil
            resolve()
            return
        }
        isResolvingCity = true
        cityLookupFailure = nil
        cityTask = Task { [weak self] in
            do {
                let resolved = try await Self.geocode(query)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.isResolvingCity = false
                guard let resolved else {
                    self.cityLookupFailure = "No place found for “\(query)”."
                    return
                }
                self.prefs.cachedCityPlace = resolved
                self.resolve()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.isResolvingCity = false
                self?.cityLookupFailure = "Could not reach the place lookup."
            }
        }
    }

    private static func geocode(_ query: String) async throws -> WeatherPlace? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(GeocodeResponse.self, from: data)
        guard let hit = payload.results?.first else { return nil }
        // "Hoboken, New Jersey" reads better on a card than a bare city name,
        // and disambiguates the two Hobokens the geocoder knows about.
        let region = hit.admin1 ?? hit.country
        let name = region.map { "\(hit.name), \($0)" } ?? hit.name
        return WeatherPlace(name: name, latitude: hit.latitude, longitude: hit.longitude)
    }

    private struct GeocodeResponse: Decodable {
        struct Hit: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let admin1: String?
            let country: String?
        }
        let results: [Hit]?
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = status
            if status.grantsLocation {
                if self.prefs.weatherUseLocation { manager.startUpdatingLocation() }
            } else {
                // Denied, restricted, or still undetermined: stop asking, drop
                // any device fix, and let the city fallback take over silently.
                manager.stopUpdatingLocation()
                self.devicePlace = nil
                self.resolve()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        let coordinate = fix.coordinate
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Name it with CLGeocoder, which is allowed here precisely because
            // Location Services *is* on. A failure just leaves the card
            // showing conditions with no place name — never an error.
            let name = await Self.reverseGeocode(fix)
            self.devicePlace = WeatherPlace(
                name: name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            self.resolve()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Fail silent: a fix that didn't arrive is not an error the user can
        // act on, and the city fallback already covers it (Guideline #3).
        Task { @MainActor [weak self] in self?.resolve() }
    }

    private static func reverseGeocode(_ location: CLLocation) async -> String {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let mark = placemarks?.first else { return "" }
        let city = mark.locality ?? mark.subAdministrativeArea ?? ""
        let region = mark.administrativeArea ?? mark.country ?? ""
        if city.isEmpty { return region }
        return region.isEmpty ? city : "\(city), \(region)"
    }
}

/// A coordinate plus a human name for it. Persisted (for the typed city) as
/// three plain values in `UserDefaults` — it is a place the user typed, not
/// device location, and the device fix is never written anywhere.
struct WeatherPlace: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
}

extension CLAuthorizationStatus {
    /// Whether this status actually yields location updates.
    ///
    /// `.authorizedWhenInUse` has to be in here: `requestWhenInUseAuthorization`
    /// — which is what Tempo calls — is exactly the request that returns it, so
    /// matching only `.authorizedAlways` would leave a *granted* Mac silently
    /// never starting the location manager, and the weather would fall back to
    /// the typed city with nothing to explain why.
    var grantsLocation: Bool {
        switch self {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }
}
