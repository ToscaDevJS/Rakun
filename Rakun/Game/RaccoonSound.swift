//
//  RaccoonSound.swift
//  Rakun
//

import Foundation

/// Efectos de sonido del mapache. Los WAV salen de `game-assets/audio/` (generados con ElevenLabs).
nonisolated enum RaccoonSound: String, CaseIterable, Sendable {
    case footstep
    case shot
    case reload
    case hit
    case death
    case victory

    /// Los sonidos que se repiten mucho tienen varias tomas para que no suenen a metralleta.
    var variants: Int {
        switch self {
        case .footstep, .shot: 3
        case .hit: 2
        default: 1
        }
    }

    /// Nombres de archivo sin extensión: `reload`, o `footstep_1`…`footstep_3` si hay variantes.
    var fileNames: [String] {
        variants == 1 ? [rawValue] : (1...variants).map { "\(rawValue)_\($0)" }
    }

    /// Todos los archivos están normalizados al mismo pico; la mezcla se hace aquí.
    var volume: Float {
        switch self {
        case .footstep: 0.35
        case .shot: 0.6
        case .reload: 0.7
        case .hit, .death: 0.9
        case .victory: 0.7
        }
    }

    /// Los sonidos largos se cortan si el mapache cambia de animación antes de que terminen.
    var isLong: Bool {
        switch self {
        case .reload, .death, .victory: true
        default: false
        }
    }

    /// Sonido que acompaña al arranque de una animación. Los pasos y los disparos no van aquí:
    /// los marcan `footstepSerial` y `shotSerial` de `RaccoonSimulation`, porque suenan varias
    /// veces dentro de una misma animación en bucle.
    init?(startOf animation: RaccoonAnimation) {
        switch animation {
        case .reload: self = .reload
        case .hit: self = .hit
        case .death: self = .death
        case .victory: self = .victory
        default: return nil
        }
    }
}
