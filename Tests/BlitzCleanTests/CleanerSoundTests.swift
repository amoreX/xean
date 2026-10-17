import AVFoundation
import Foundation
import Testing

@testable import BlitzClean

@MainActor
struct CleanerSoundTests {
  @Test func bundledCuelumeCuesDecodeAsShortStereoAudio() throws {
    for cue in CleanerCue.allCases {
      let player = try AVAudioPlayer(contentsOf: #require(cue.url))
      #expect(player.duration > 0.01 && player.duration < 2)
      #expect(player.numberOfChannels == 2)
      let file = try AVAudioFile(forReading: #require(cue.url))
      #expect(file.fileFormat.sampleRate == 48_000)
    }
  }

  @Test func failedOrPartialCleanupNeverUsesTheSuccessCue() {
    #expect(CleanerCue.cleanup(removed: 0, kept: 3) == .error)
    #expect(CleanerCue.cleanup(removed: 2, kept: 1) == .warning)
    #expect(CleanerCue.cleanup(removed: 2, kept: 0) == .success)
  }
}
