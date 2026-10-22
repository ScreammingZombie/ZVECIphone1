import SwiftUI

/// Paleta zombie: verdes, negros y grises (la misma línea que Zcleaner, Zombie Music Library y la versión Android).
enum Pal {
    static let bg = Color(red: 10 / 255, green: 15 / 255, blue: 10 / 255)
    static let panel = Color(red: 20 / 255, green: 26 / 255, blue: 20 / 255)
    static let panel2 = Color(red: 30 / 255, green: 38 / 255, blue: 30 / 255)
    static let green = Color(red: 124 / 255, green: 198 / 255, blue: 43 / 255)
    static let darkGreen = Color(red: 46 / 255, green: 107 / 255, blue: 34 / 255)
    static let text = Color(red: 230 / 255, green: 237 / 255, blue: 224 / 255)
    static let gray = Color(red: 140 / 255, green: 150 / 255, blue: 138 / 255)
    static let warn = Color(red: 224 / 255, green: 195 / 255, blue: 74 / 255)
}

extension Font {
    /// Dark Zombie: solo para el nombre de la app (no tiene acentos).
    static func title(_ size: CGFloat) -> Font { .custom("DarkZombie", size: size) }
    /// Scary Zombie: botones y títulos de tarjetas.
    static func zombie(_ size: CGFloat) -> Font { .custom("ScaryZombie", size: size) }
}
