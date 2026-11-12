import Foundation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let quality = "bmusic.quality"
        static let volume = "bmusic.volume"
        static let repeatMode = "bmusic.repeat"
        static let shuffle = "bmusic.shuffle"
        static let appearance = "bmusic.appearance"
        static let showPlayCount = "bmusic.showPlayCount"
        static let lyrics = "bmusic.lyrics"
        static let gapless = "bmusic.gapless"
        static let sleepMinutes = "bmusic.sleepMinutes"
        static let nowPlaying = "bmusic.nowPlaying"
        static let autoNext = "bmusic.autoNext"
    }

    private let defaults: UserDefaults

    @Published var quality: PlaybackQuality {
        didSet { defaults.set(quality.rawValue, forKey: Key.quality) }
    }
    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: Key.volume) }
    }
    @Published var repeatMode: RepeatMode {
        didSet { defaults.set(repeatMode.rawValue, forKey: Key.repeatMode) }
    }
    @Published var shuffle: Bool {
        didSet { defaults.set(shuffle, forKey: Key.shuffle) }
    }
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    @Published var showPlayCount: Bool {
        didSet { defaults.set(showPlayCount, forKey: Key.showPlayCount) }
    }
    @Published var lyricsEnabled: Bool {
        didSet { defaults.set(lyricsEnabled, forKey: Key.lyrics) }
    }
    @Published var gaplessPlayback: Bool {
        didSet { defaults.set(gaplessPlayback, forKey: Key.gapless) }
    }
    @Published var autoPlayNext: Bool {
        didSet { defaults.set(autoPlayNext, forKey: Key.autoNext) }
    }
    @Published var systemNowPlaying: Bool {
        didSet { defaults.set(systemNowPlaying, forKey: Key.nowPlaying) }
    }
    @Published var sleepMinutes: Int {
        didSet { defaults.set(sleepMinutes, forKey: Key.sleepMinutes) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        quality = PlaybackQuality(rawValue: defaults.string(forKey: Key.quality) ?? "") ?? .lossless
        volume = defaults.object(forKey: Key.volume) as? Double ?? 0.72
        repeatMode = RepeatMode(rawValue: defaults.string(forKey: Key.repeatMode) ?? "") ?? .off
        shuffle = defaults.bool(forKey: Key.shuffle)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        showPlayCount = defaults.object(forKey: Key.showPlayCount) as? Bool ?? true
        lyricsEnabled = defaults.object(forKey: Key.lyrics) as? Bool ?? true
        gaplessPlayback = defaults.object(forKey: Key.gapless) as? Bool ?? true
        autoPlayNext = defaults.object(forKey: Key.autoNext) as? Bool ?? true
        systemNowPlaying = defaults.object(forKey: Key.nowPlaying) as? Bool ?? true
        sleepMinutes = defaults.integer(forKey: Key.sleepMinutes)
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func cycleRepeatMode() {
        var mode = repeatMode
        mode.advance()
        repeatMode = mode
    }
}
