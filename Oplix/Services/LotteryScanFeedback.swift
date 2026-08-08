//
//  LotteryScanFeedback.swift
//  Oplix
//

import AudioToolbox
import AVFoundation
import UIKit

enum LotteryScanFeedback {
    /// Pleasant confirmation (system "Tink").
    private static let successSound: SystemSoundID = 1057
    /// Harsh alert beep.
    private static let errorSound: SystemSoundID = 1006

    private static let synthesizer = AVSpeechSynthesizer()

    static func playSuccess() {
        AudioServicesPlaySystemSound(successSound)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func playError() {
        AudioServicesPlaySystemSound(errorSound)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            AudioServicesPlaySystemSound(errorSound)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Shift-close success: beep + speak only the ending # from this scan.
    static func announceEnding(bin: String, ending: String) {
        playSuccess()
        speak(spokenDigits(ending))
    }

    /// Pack assign / return after camera already beeped — speak only the ticket #.
    static func speakTicket(_ ticket: String, game: String? = nil) {
        speak(spokenDigits(ticket))
    }

    /// Beep + speak ticket (when not already playing success elsewhere).
    static func announceTicket(_ ticket: String, game: String? = nil) {
        playSuccess()
        speakTicket(ticket)
    }

    static func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if Thread.isMainThread {
            speakOnMain(trimmed)
        } else {
            DispatchQueue.main.async { speakOnMain(trimmed) }
        }
    }

    private static func speakOnMain(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.05
        utterance.preUtteranceDelay = 0.05
        utterance.volume = 1.0
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    /// Prefer digit-by-digit so "44" / "00" are clear over the register noise.
    private static func spokenDigits(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return raw }
        return digits.map { String($0) }.joined(separator: " ")
    }
}
