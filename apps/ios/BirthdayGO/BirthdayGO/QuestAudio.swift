import AVFoundation
import Foundation

final class QuestAudio: @unchecked Sendable {
    static let shared = QuestAudio()

    private var jump: AVAudioPlayer?
    private var clear: AVAudioPlayer?
    private var music: AVAudioPlayer?
    private var sessionReady = false

    private init() {}

    func preloadLevel1() {
        activateSession()
        if jump == nil {
            jump = player(name: "smb_jump-small", ext: "wav")
        }
        if clear == nil {
            clear = player(name: "smb_world_clear", ext: "wav")
        }
    }

    func playJump() {
        play(&jump, name: "smb_jump-small", ext: "wav")
    }

    func playWorldClear() {
        stopMusic()
        play(&clear, name: "smb_world_clear", ext: "wav")
    }

    func startRetroWave() {
        startMusic(name: "freesound_community-retro-wave-style-track-59892", ext: "mp3")
    }

    func pauseMusic() {
        music?.pause()
    }

    func stopMusic() {
        music?.stop()
        music = nil
    }

    private func play(_ slot: inout AVAudioPlayer?, name: String, ext: String) {
        activateSession()
        if slot == nil {
            slot = player(name: name, ext: ext)
        }
        guard let player = slot else { return }
        player.currentTime = 0
        player.play()
    }

    private func startMusic(name: String, ext: String) {
        activateSession()
        if let music, music.url?.deletingPathExtension().lastPathComponent == name {
            if !music.isPlaying { music.play() }
            return
        }
        stopMusic()
        music = player(name: name, ext: ext)
        music?.numberOfLoops = -1
        music?.volume = 0.42
        music?.play()
    }

    private func player(name: String, ext: String) -> AVAudioPlayer? {
        let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        return player
    }

    private func activateSession() {
        guard !sessionReady else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        sessionReady = true
    }
}
