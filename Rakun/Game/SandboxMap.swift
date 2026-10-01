//
//  SandboxMap.swift
//  Rakun
//

import simd

/// Mapa básico de pruebas: un cuadrado con obstáculos circulares. Coordenadas en el plano XZ (metros).
nonisolated struct SandboxMap: Sendable {
    nonisolated enum ObstacleKind: Sendable {
        case crate
        case barrel
        case target
    }

    nonisolated struct Obstacle: Sendable {
        var center: SIMD2<Float>
        var radius: Float
        var kind: ObstacleKind
    }

    /// Mitad del lado del mapa.
    var halfSize: Float
    var obstacles: [Obstacle]
    /// Muñeco al que apunta el mapache en el modo «apuntar».
    var target: SIMD2<Float>

    static let basic = SandboxMap(
        halfSize: 6,
        obstacles: [
            Obstacle(center: SIMD2(0, -4), radius: 0.25, kind: .target),
            Obstacle(center: SIMD2(-2.5, -1.5), radius: 0.55, kind: .crate),
            Obstacle(center: SIMD2(2.5, 1.5), radius: 0.55, kind: .crate),
            Obstacle(center: SIMD2(3, -3), radius: 0.55, kind: .crate),
            Obstacle(center: SIMD2(-3, 3), radius: 0.3, kind: .barrel),
            Obstacle(center: SIMD2(1.5, -1.5), radius: 0.3, kind: .barrel),
            Obstacle(center: SIMD2(-1.5, 3.5), radius: 0.3, kind: .barrel),
        ],
        target: SIMD2(0, -4)
    )

    /// Devuelve la posición más cercana a `point` que no atraviesa obstáculos ni sale del mapa.
    func resolve(_ point: SIMD2<Float>, radius: Float) -> SIMD2<Float> {
        var p = point
        for obstacle in obstacles {
            let delta = p - obstacle.center
            let minDistance = obstacle.radius + radius
            let distance = simd_length(delta)
            if distance < minDistance {
                let direction = distance > 1e-5 ? delta / distance : SIMD2<Float>(0, 1)
                p = obstacle.center + direction * minDistance
            }
        }
        let limit = halfSize - radius
        return simd_clamp(p, SIMD2(repeating: -limit), SIMD2(repeating: limit))
    }
}
