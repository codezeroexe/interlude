import Testing
@testable import Interlude

struct WeatherSymbolTests {
    @Test func mapsWMOCodes() {
        #expect(WeatherStore.symbol(code: 0, isDay: true) == "sun.max")
        #expect(WeatherStore.symbol(code: 0, isDay: false) == "moon.stars")
        #expect(WeatherStore.symbol(code: 63, isDay: true) == "cloud.rain")
        #expect(WeatherStore.symbol(code: 81, isDay: true) == "cloud.rain")
        #expect(WeatherStore.symbol(code: 95, isDay: true) == "cloud.bolt.rain")
        #expect(WeatherStore.symbol(code: 3, isDay: true) == "cloud")
    }
}
