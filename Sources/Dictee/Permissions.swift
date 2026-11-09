import AppKit
import AVFoundation
import ApplicationServices

/// Les trois autorisations dont l'app a besoin, et le chemin pour les obtenir.
enum Permissions {
    enum Volet: String {
        case micro = "Privacy_Microphone"
        case accessibilite = "Privacy_Accessibility"
        case surveillance = "Privacy_ListenEvent"
        case reconnaissance = "Privacy_SpeechRecognition"
    }

    static var microStatut: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    static var microOK: Bool { microStatut == .authorized }
    static var accessibiliteOK: Bool { AXIsProcessTrusted() }
    static var surveillanceOK: Bool { CGPreflightListenEventAccess() }

    static var toutesOK: Bool { microOK && accessibiliteOK && surveillanceOK }

    static func ouvrir(_ volet: Volet) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(volet.rawValue)")!
        NSWorkspace.shared.open(url)
    }

    /// La première autorisation qui manque, dans l'ordre : micro, accessibilité, surveillance de l'entrée.
    static var premierManquant: Volet? {
        if !microOK { return .micro }
        if !accessibiliteOK { return .accessibilite }
        if !surveillanceOK { return .surveillance }
        return nil
    }

    static func resume() -> String {
        let micro = microOK ? "oui" : "non(\(microStatut.rawValue))"
        return "micro=\(micro) accessibilite=\(accessibiliteOK ? "oui" : "non") surveillance=\(surveillanceOK ? "oui" : "non")"
    }

    /// Demande ce qui manque, une chose à la fois (le système affiche sa propre fenêtre),
    /// et ouvre le bon volet des Réglages Système. Renvoie le volet ouvert, s'il y en a un.
    @MainActor
    @discardableResult
    static func demanderLePremierManquant() async -> Volet? {
        guard let volet = premierManquant else { return nil }
        switch volet {
        case .micro:
            if microStatut == .notDetermined {
                let accorde = await AVCaptureDevice.requestAccess(for: .audio)
                Log.ecrire("micro : demande faite, réponse = \(accorde ? "accordé" : "refusé")")
                if accorde { return await demanderLePremierManquant() }
            }
            ouvrir(.micro)
        case .accessibilite:
            // Affiche la fenêtre du système et inscrit l'app dans la liste.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            ouvrir(.accessibilite)
        case .surveillance:
            _ = CGRequestListenEventAccess()
            ouvrir(.surveillance)
        case .reconnaissance:
            ouvrir(.reconnaissance)
        }
        Log.ecrire("autorisation manquante, volet ouvert : \(volet.rawValue)")
        return volet
    }
}
