//
//  RaccoonAnimation.swift
//  Rakun
//

import Foundation

/// Las 11 animaciones del mapache. Cada una vive en su propio USDZ (`raccoon_<rawValue>.usdz`).
nonisolated enum RaccoonAnimation: String, CaseIterable, Sendable, Identifiable {
    case idle
    case run
    case runBackward = "run_backward"
    case walk
    case strafeLeft = "strafe_left"
    case strafeRight = "strafe_right"
    case fire
    case reload
    case hit
    case death
    case victory

    var id: String { rawValue }

    var resourceName: String {
        switch self {
        // Los laterales de Mixamo están nombrados al revés: `rifle-strafe-left.fbx` se desplaza
        // hacia -X, que es la derecha del mapache (su mano izquierda está en +X). Aquí
        // `strafeLeft` significa «hacia su izquierda», así que usa el archivo contrario.
        case .strafeLeft: "raccoon_strafe_right"
        case .strafeRight: "raccoon_strafe_left"
        default: "raccoon_\(rawValue)"
        }
    }

    var loops: Bool {
        switch self {
        case .fire, .reload, .hit, .death: false
        default: true
        }
    }

    /// Segundos que se reproduce una acción antes de volver al movimiento normal.
    /// `nil` en las animaciones en bucle y en `death`, que se queda en el último fotograma.
    var actionDuration: TimeInterval? {
        switch self {
        case .fire: 0.27
        case .reload: 3.3
        // La animación dura 2,3 s con la recuperación; en el juego basta con el principio.
        case .hit: 0.6
        default: nil
        }
    }

    var title: String {
        switch self {
        case .idle: "Quieto"
        case .run: "Correr"
        case .runBackward: "Atrás"
        case .walk: "Andar"
        case .strafeLeft: "Lateral izq."
        case .strafeRight: "Lateral der."
        case .fire: "Disparar"
        case .reload: "Recargar"
        case .hit: "Daño"
        case .death: "Morir"
        case .victory: "Victoria"
        }
    }
}
