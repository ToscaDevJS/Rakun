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
        /// Segundos entre disparos con el fuego automático.
        var fireInterval: TimeInterval = 0.6
        /// Tras un disparo, tiempo durante el que andar o correr usa la animación de disparar
        /// en marcha en vez de la normal.
        var movingFireWindow: TimeInterval = 0.9
    }

    var tuning = Tuning()

    private(set) var position = SIMD2<Float>(0, 0)
    private(set) var yaw: Float = 0
    private(set) var speed: Float = 0
    private(set) var animation: RaccoonAnimation = .idle
    /// Cambia cada vez que hay que (re)lanzar `animation`, aunque sea la misma (p. ej. dos disparos).
    private(set) var animationSerial = 0
    /// Aumenta en uno cada vez que un pie toca el suelo; quien pone el sonido solo mira si cambia.
    private(set) var footstepSerial = 0
    /// Aumenta en uno con cada disparo, sea de pie o en marcha.
    private(set) var shotSerial = 0
    private(set) var isDead = false
    /// Segundos que lleva puesta la animación actual.
    private var animationTime: TimeInterval = 0

    private var action: RaccoonAnimation?
    private var actionRemaining: TimeInterval = 0
    /// Animación en bucle forzada desde la galería; se cancela al mover el joystick.
    private var preview: RaccoonAnimation?
    private var firingRemaining: TimeInterval = 0
    private var fireCooldown: TimeInterval = 0

    var facing: SIMD2<Float> { SIMD2(sin(yaw), cos(yaw)) }

    /// Lanza una animación a mano: acción de un solo uso, muerte o vista previa en bucle.
    mutating func trigger(_ requested: RaccoonAnimation) {
        guard !isDead else { return }
        if requested == .fire {
            fire()
        } else if requested == .death {
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
        if requested != .fire { setAnimation(requested, restart: true) }
    }

    private mutating func fire() {
        shotSerial += 1
        preview = nil
        action = .fire
        actionRemaining = RaccoonAnimation.fire.actionDuration ?? 0
        firingRemaining = tuning.movingFireWindow
        // Si ya va disparando en marcha, la animación sigue su bucle: relanzarla en cada
        // disparo la haría empezar de cero una y otra vez.
        if animation != .walkFire, animation != .runFire {
            setAnimation(.fire, restart: true)
        }
    }

    mutating func reset() {
        let serial = animationSerial
        let footsteps = footstepSerial
        let shots = shotSerial
        let tuning = tuning
        self = RaccoonSimulation()
        self.tuning = tuning
        animationSerial = serial + 1
        footstepSerial = footsteps
        shotSerial = shots
    }

    /// - Parameters:
    ///   - stick: joystick, x a la derecha e y hacia arriba, magnitud 0…1.
    ///   - aimTarget: si no es `nil`, el mapache mira siempre a ese punto y se mueve de lado o de espaldas.
    ///   - firing: fuego automático: dispara cada `fireInterval` mientras sea `true`.
    mutating func step(dt: TimeInterval, stick: SIMD2<Float>, aimTarget: SIMD2<Float>?, firing: Bool = false,
                       map: SandboxMap) {
        guard !isDead else { return }

        advanceFootsteps(dt: dt)

        if action != nil {
            actionRemaining -= dt
            if actionRemaining <= 0 { action = nil }
        }

        firingRemaining = max(0, firingRemaining - dt)
        fireCooldown = max(0, fireCooldown - dt)
        // El fuego automático no interrumpe una recarga ni un golpe.
        if firing, fireCooldown <= 0, action != .reload, action != .hit {
            fire()
            fireCooldown = tuning.fireInterval
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

        var shown = action ?? preview ?? gait
        // Disparando en marcha se usa la variante de andar o correr: el disparo de pie patinaría.
        if firingRemaining > 0, action == nil || action == .fire, let variant = gait.firingVariant {
            shown = variant
        }
        setAnimation(shown, restart: false)
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
        animationTime = 0
    }

    /// Avanza el reloj de la animación que se ha estado viendo durante `dt` y cuenta los
    /// contactos de pie que han caído en ese tramo, incluidas las vueltas del bucle.
    private mutating func advanceFootsteps(dt: TimeInterval) {
        let previous = animationTime
        animationTime += dt * animation.playbackRate
        guard let footsteps = animation.footsteps else { return }
        for contact in footsteps.contacts {
            let before = ((previous - contact) / footsteps.cycle).rounded(.down)
            let after = ((animationTime - contact) / footsteps.cycle).rounded(.down)
            footstepSerial += Int(after - before)
        }
    }
}
