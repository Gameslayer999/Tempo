import Combine
import Foundation

/// Current conditions for the lock-screen weather card (decision 058).
///
/// Source is **Open-Meteo** (`api.open-meteo.com`), chosen because it needs no
/// API key and no account: WeatherKit — the obvious Apple answer — requires a
/// real Team ID and a `com.apple.developer.weatherkit` entitlement, and
/// `dist/Tempo.app` is ad-hoc signed with no team (decision 018), so it cannot
/// be used here at all.
///
/// One request every `refreshInterval`, and only while the feature is on.
/// Everything fails silent (Agent Guideline #3): no network, a denied
/// location, a malformed payload — each leaves `reading` at its last good
/// value (or nil) and the card simply isn't posted.
@MainActor
final class WeatherService: ObservableObject {
    /// Latest conditions, or nil until the first successful fetch.
    @Published private(set) var reading: WeatherReading?
    /// Why there is no reading, for the Settings pane to show. Never logged:
    /// it can carry the resolved place name.
    @Published private(set) var failure: String?

    /// Open-Meteo advertises `interval: 900` on the current block — the data
    /// itself only changes every 15 minutes, so polling faster would spend
    /// requests to re-read the same numbers.
    static let refreshInterval: TimeInterval = 900

    private let location: LocationService
    private let prefs: Preferences
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    init(location: LocationService, prefs: Preferences) {
        self.location = location
        self.prefs = prefs

        // A place arriving (first location fix, or a city typed in Settings)
        // is what makes the very first fetch possible, so it triggers one
        // rather than waiting out the 15-minute timer.
        location.$place
            .removeDuplicates()
            .sink { [weak self] place in
                guard let self, self.isRunning, place != nil else { return }
                self.fetch()
            }
            .store(in: &cancellables)

        // The unit is a formatting choice, but Open-Meteo does the conversion
        // server-side, so changing it re-fetches rather than converting here.
        prefs.$weatherUnit
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.isRunning else { return }
                self.fetch()
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        location.start()
        fetch()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetch() }
        }
        // Tolerance lets macOS coalesce this with other timers instead of
        // waking the CPU on its own schedule for a 15-minute poll.
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
        location.stop()
        reading = nil
        failure = nil
    }

    /// Fetch now, regardless of the timer — used by Settings' Refresh button
    /// and by the first location fix.
    func fetch() {
        guard let place = location.place else {
            failure = "No location yet."
            return
        }
        task?.cancel()
        let unit = prefs.weatherUnit
        task = Task { [weak self] in
            do {
                let current = try await Self.load(place: place, unit: unit)
                guard !Task.isCancelled else { return }
                self?.reading = current
                self?.failure = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // Keep the last good reading rather than blanking the card on
                // one dropped request; the message only reaches Settings.
                self?.failure = (error as? URLError)?.localizedDescription ?? "Weather unavailable."
            }
        }
    }

    // MARK: Network

    private static func load(place: WeatherPlace, unit: TemperatureUnit) async throws -> WeatherReading {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: unit.openMeteoValue),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // No cache: a 15-minute poll that gets served a cached body is a
        // stale signal, and UI Principle #4 forbids showing one.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return WeatherReading(
            temperature: payload.current.temperature_2m,
            apparentTemperature: payload.current.apparent_temperature,
            condition: WeatherCondition(wmoCode: payload.current.weather_code),
            isDay: payload.current.is_day == 1,
            unit: unit,
            placeName: place.name,
            observedAt: Date()
        )
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
        }
        let current: Current
    }
}

/// One set of current conditions, already in the unit the user asked for.
struct WeatherReading: Equatable {
    var temperature: Double
    var apparentTemperature: Double
    var condition: WeatherCondition
    var isDay: Bool
    var unit: TemperatureUnit
    /// Where these conditions are, for the card's subtitle. Empty when the
    /// place could not be named (reverse geocoding is best-effort).
    var placeName: String
    var observedAt: Date

    /// "80°" — the card has room for a magnitude, not for decimals.
    var temperatureText: String { "\(Int(temperature.rounded()))°" }
    var apparentText: String { "\(Int(apparentTemperature.rounded()))°" }

    /// SF Symbol for the condition, day/night aware where the symbol set
    /// distinguishes them.
    var symbolName: String { condition.symbolName(isDay: isDay) }

    /// "80° Clear · Hoboken" / "80° Clear" when the place has no name.
    var summary: String {
        let core = "\(temperatureText) \(condition.title)"
        return placeName.isEmpty ? core : "\(core) · \(placeName)"
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case fahrenheit, celsius

    var id: String { rawValue }
    var title: String { self == .fahrenheit ? "Fahrenheit (°F)" : "Celsius (°C)" }
    var openMeteoValue: String { self == .fahrenheit ? "fahrenheit" : "celsius" }

    /// What this Mac's region formats temperatures in, so a fresh install
    /// starts on the right one instead of on a US default.
    static var systemDefault: TemperatureUnit {
        if #available(macOS 13.0, *) {
            return Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
        }
        return .fahrenheit
    }
}

/// WMO weather-interpretation codes, which is what Open-Meteo reports, folded
/// into the handful of conditions a one-line card can actually say.
enum WeatherCondition: Equatable {
    case clear, mostlyClear, partlyCloudy, overcast, fog
    case drizzle, freezingDrizzle, rain, freezingRain, rainShowers
    case snow, snowGrains, snowShowers
    case thunderstorm, thunderstormHail
    case unknown

    init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1: self = .mostlyClear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57: self = .freezingDrizzle
        case 61, 63, 65: self = .rain
        case 66, 67: self = .freezingRain
        case 71, 73, 75: self = .snow
        case 77: self = .snowGrains
        case 80, 81, 82: self = .rainShowers
        case 85, 86: self = .snowShowers
        case 95: self = .thunderstorm
        case 96, 99: self = .thunderstormHail
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .clear: return "Clear"
        case .mostlyClear: return "Mostly clear"
        case .partlyCloudy: return "Partly cloudy"
        case .overcast: return "Overcast"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .freezingDrizzle: return "Freezing drizzle"
        case .rain: return "Rain"
        case .freezingRain: return "Freezing rain"
        case .rainShowers: return "Rain showers"
        case .snow: return "Snow"
        case .snowGrains: return "Snow grains"
        case .snowShowers: return "Snow showers"
        case .thunderstorm: return "Thunderstorm"
        case .thunderstormHail: return "Thunderstorm with hail"
        case .unknown: return "Weather"
        }
    }

    func symbolName(isDay: Bool) -> String {
        switch self {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mostlyClear: return isDay ? "sun.min.fill" : "moon.fill"
        case .partlyCloudy: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .freezingDrizzle: return "cloud.sleet.fill"
        case .rain: return "cloud.rain.fill"
        case .freezingRain: return "cloud.sleet.fill"
        case .rainShowers: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .snowGrains: return "cloud.snow.fill"
        case .snowShowers: return "cloud.snow.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .thunderstormHail: return "cloud.bolt.rain.fill"
        case .unknown: return "thermometer.medium"
        }
    }
}
