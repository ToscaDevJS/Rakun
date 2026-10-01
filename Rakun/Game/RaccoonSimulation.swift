//
//  RaccoonSimulation.swift
//  Rakun
//

import Foundation
import simd

/// Lógica del mapache sin SceneKit: movimiento, giro y qué animación toca en cada momento.
///
/// Convenciones: plano XZ en metros, el mapache mira hacia +Z con `yaw == 0` y la cámara mira
/// desde +Z, así que «arriba» en el joystick es -Z y «derecha» es +X.
nonisolated struct RaccoonSimulation: Sendable {
    nonisolated struct Tuning: Sendable {
        // Las velocidades de run y walk son el avance que se quitó a cada ciclo al dejarlas
        // in place (0,94 m / 0,73 s y 0,55 m / 1,37 s): así los pies no patinan.
        var runSpeed: Float = 1.28
        var walkSpeed: Float = 0.40
        // Los dos laterales avanzaban distinto en el original (1,14 y 1,34 m/s); se usa un valor
        // intermedio para que moverse a un lado no sea más rápido que al otro.
        var strafeSpeed: Float = 1.2
        var backwardSpeed: Float = 1.0
        /// Radianes por segundo.
        var turnRate: Float = 10
        var deadZone: Float = 0.15
        /// Por debajo de este empuje del joystick anda; por encima, corre.
        var runThreshold: Float = 0.6
        var radius: Float = 0.22
    }

    var tuning = Tuning()

    private(set) var position = SIMD2<Float>(0, 0)
    private(set) var yaw: Float = 0
    private(set) var speed: Float = 0
    private(set) var animation: RaccoonAnimation = .idle
    /// Cambia cada vez que hay que (re)lanzar `animation`, aunque sea la misma (p. ej. dos disparos).
    private(set) var animationSerial = 0
    private(set) var isDead = false

    private var action: RaccoonAnimation?
    private var actionRemaining: TimeInterval = 0
    /// Animación en bucle forzada desde la galería; se cancela al mover el joystick.
    private var preview: RaccoonAnimation?

    var facing: SIMD2<Float> { SIMD2(sin(yaw), cos(yaw)) }

    /// Lanza una animación a mano: acción de un solo uso, muerte o vista previa en bucle.
    mutating func trigger(_ requested: RaccoonAnimation) {
        guard !isDead else { return }
        if requested == .death {
            isDead = true
            action = nil
            preview = nil
            speed = 0
        } else if let duration = requested.actionDuration {
            action = requested
            actionRemaining = duration
        } else {
            action = nil
            preview = requested
        }
        setAnimation(requested, restart: true)
    }

    mutating func reset() {
        let serial = animationSerial
        let tuning = tuning
        self = RaccoonSimulation()
        self.tuning = tuning
        animationSerial = serial + 1
    }

    /// - Parameters:
    ///   - stick: joystick, x a la derecha e y hacia arriba, magnitud 0…1.
    ///   - aimTarget: si no es `nil`, el mapache mira siempre a ese punto y se mueve de lado o de espaldas.
    mutating func step(dt: TimeInterval, stick: SIMD2<Float>, aimTarget: SIMD2<Float>?, map: SandboxMap) {
        guard !isDead else { return }

        if action != nil {
            actionRemaining -= dt
            if actionRemaining <= 0 { action = nil }
        }

        let magnitude = min(simd_length(stick), 1)
        // El golpe lo deja clavado en el sitio; disparar y recargar no.
        let canMove = magnitude > tuning.deadZone && action != .hit
        var gait = RaccoonAnimation.idle
        var desiredFacing: SIMD2<Float>?
        speed = 0

        if let aimTarget {
            let toTarget = aimTarget - position
            if simd_length(toTarget) > 1e-3 { desiredFacing = simd_normalize(toTarget) }
        }

        if canMove {
            preview = nil
            let direction = simd_normalize(SIMD2(stick.x, -stick.y))
            if aimTarget == nil { desiredFacing = direction }
            gait = chooseGait(moving: direction, facing: desiredFacing ?? facing, magnitude: magnitude)
            speed = gaitSpeed(gait)
            position = map.resolve(position + direction * speed * Float(dt), radius: tuning.radius)
        }

        if let desiredFacing {
            turn(toward: atan2(desiredFacing.x, desiredFacing.y), dt: dt)
        }

        setAnimation(action ?? preview ?? gait, restart: false)
    }

    private func chooseGait(moving direction: SIMD2<Float>, facing: SIMD2<Float>, magnitude: Float) -> RaccoonAnimation {
        let forward = simd_dot(direction, facing)
        // Con el mapache mirando a +Z y la Y arriba, su izquierda es +X.
        let left = simd_dot(direction, SIMD2(facing.y, -facing.x))
        if abs(forward) >= abs(left) {
            if forward < 0 { return .runBackward }
            return magnitude < tuning.runThreshold ? .walk : .run
        }
        return left > 0 ? .strafeLeft : .strafeRight
    }

    private func gaitSpeed(_ gait: RaccoonAnimation) -> Float {
        switch gait {
        case .run: tuning.runSpeed
        case .walk: tuning.walkSpeed
        case .runBackward: tuning.backwardSpeed
        case .strafeLeft, .strafeRight: tuning.strafeSpeed
        default: 0
        }
    }

    private mutating func turn(toward target: Float, dt: TimeInterval) {
        var delta = (target - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        let maxStep = tuning.turnRate * Float(dt)
        yaw += min(max(delta, -maxStep), maxStep)
    }

    private mutating func setAnimation(_ new: RaccoonAnimation, restart: Bool) {
        guard new != animation || restart else { return }
        animation = new
        animationSerial += 1
    }
}
