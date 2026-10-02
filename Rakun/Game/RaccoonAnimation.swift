//
//  RaccoonAnimation.swift
//  Rakun
//

import Foundation

/// Las animaciones del mapache. Cada una vive en su propio USDZ (`raccoon_<rawValue>.usdz`).
nonisolated enum RaccoonAnimation: String, CaseIterable, Sendable, Identifiable {
    case idle
    case run
    case runBackward = "run_backward"
    case walk
    case strafeLeft = "strafe_left"
    case strafeRight = "strafe_right"
    case walkFire = "walk_fire"
    case runFire = "run_fire"
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

    /// Variante de este paso en la que el mapache dispara sin dejar de avanzar.
    var firingVariant: RaccoonAnimation? {
        switch self {
        case .walk: .walkFire
        case .run: .runFire
        default: nil
        }
    }

    /// Velocidad de reproducción. El original de `run_fire` avanza a 0,84 m/s y el mapache
    /// corre a 1,28 m/s: se acelera en esa proporción para que los pies no patinen.
    var playbackRate: Double {
        self == .runFire ? 1.52 : 1
    }

    /// Duración del ciclo y momentos (en segundos desde su inicio) en que un pie toca el suelo.
    /// Medido en Blender sobre los originales, con la altura de `LeftToeBase` y `RightToeBase`.
    var footsteps: (cycle: TimeInterval, contacts: [TimeInterval])? {
        switch self {
        case .run: (22.0 / 30, [0.233, 0.633])
        case .walk: (41.0 / 30, [0.4, 1.15])
        case .runBackward: (16.0 / 30, [0.133, 0.4])
        case .walkFire: (40.0 / 30, [0.4, 1.133])
        case .runFire: (28.0 / 30, [0.267, 0.767])
        // Usa `rifle-strafe-right.fbx` (ver `resourceName`). Apenas levanta los pies (2-4 cm),
        // así que los contactos son aproximados.
        case .strafeLeft: (16.0 / 30, [0.17, 0.43])
        // Usa `rifle-strafe-left.fbx`.
        case .strafeRight: (20.0 / 30, [0.25, 0.567])
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
        case .walkFire: "Andar disp."
        case .runFire: "Correr disp."
        case .fire: "Disparar"
        case .reload: "Recargar"
        case .hit: "Daño"
        case .death: "Morir"
        case .victory: "Victoria"
        }
    }
}
