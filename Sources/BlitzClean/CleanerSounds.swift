import AVFoundation
import AppKit

enum CleanerCue: String, CaseIterable {
  case tap, select, toggle, ready, success, warning, error

  var url: URL? {
    Bundle.module.url(forResource: rawValue, withExtension: "wav", subdirectory: "Cuelume")
  }

  static func cleanup(removed: Int, kept: Int) -> Self {
    removed == 0 ? .error : kept > 0 ? .warning : .success
  }
}

@MainActor
final class CleanerSounds {
  let volume = 0.7
  private let playbackAllowed: Bool
  private var player: AVAudioPlayer?
  private var lastPlay: TimeInterval = -.infinity

  init(playbackAllowed: Bool? = nil) {
    self.playbackAllowed = playbackAllowed ?? (Bundle.main.bundleURL.pathExtension == "app")
  }

  func play(_ cue: CleanerCue) {
    guard playbackAllowed, NSApp?.isActive == true else { return }
    let now = ProcessInfo.processInfo.systemUptime
    if [.tap, .select, .toggle].contains(cue), now - lastPlay < 0.08 { return }
    guard let url = cue.url, let next = try? AVAudioPlayer(contentsOf: url) else { return }
    player?.stop()
    next.volume = Float(volume)
    player = next
    if next.play() { lastPlay = now }
  }

}
