//
//  SandboxScene.swift
//  Rakun
//

#if canImport(SceneKit)
import SceneKit
import Synchronization

/// Banco de pruebas: el mapache en un mapa básico con cámara cenital.
///
/// La simulación avanza en el hilo de render de SceneKit (`renderer(_:updateAtTime:)`); la interfaz
/// solo deja órdenes en `input`, protegido con un cerrojo.
nonisolated final class SandboxScene: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    nonisolated struct HUD: Equatable, Sendable {
        var animation: RaccoonAnimation = .idle
        var position = SIMD2<Float>(0, 0)
        var speed: Float = 0
        var isDead = false
        /// Fotogramas por segundo reales, medidos en el hilo de render.
        var fps = 0
    }

    private nonisolated struct Input: Sendable {
        var stick = SIMD2<Float>(0, 0)
        var aimsAtTarget = false
        var zoomedIn = false
        var soundEnabled = true
        var autoFire = false
        var triggers: [RaccoonAnimation] = []
        var resetRequested = false
    }

    let scene = SCNScene()
    let cameraNode = SCNNode()
    let character: RaccoonCharacter
    let audio: SandboxAudio
    let map: SandboxMap
    private(set) var simulation = RaccoonSimulation()

    /// Se llama desde el hilo de render, como mucho 10 veces por segundo.
    var onHUD: (@Sendable (HUD) -> Void)?

    private let input = Mutex(Input())
    private var lastTime: TimeInterval?
    private var lastHUD: HUD?
    private var hudCooldown: TimeInterval = 0
    private var fps = 0
    private var fpsFrames = 0
    private var fpsWindowStart: TimeInterval?
    /// Últimos contadores de la simulación a los que ya se les puso sonido.
    private var soundedFootstep = 0
    private var soundedShot = 0
    private var soundedAnimation = 0
    private var cameraOffset = SandboxScene.farCamera

    private static let farCamera = SIMD3<Float>(0, 6, 4)
    private static let nearCamera = SIMD3<Float>(0, 2.4, 2.6)
    private static let lookHeight = SIMD3<Float>(0, 0.4, 0)

    init(map: SandboxMap = .basic, bundle: Bundle = .main) throws {
        self.map = map
        character = try RaccoonCharacter(bundle: bundle)
        audio = SandboxAudio(bundle: bundle)
        super.init()
        buildMap()
        buildLights()
        buildCamera()
        cameraNode.addChildNode(audio.node)
        scene.rootNode.addChildNode(character.node)
        character.apply(simulation)
    }

    // MARK: Órdenes desde la interfaz

    func setStick(_ stick: SIMD2<Float>) {
        input.withLock { $0.stick = stick }
    }

    func setAimsAtTarget(_ aims: Bool) {
        input.withLock { $0.aimsAtTarget = aims }
    }

    func setZoomedIn(_ zoomedIn: Bool) {
        input.withLock { $0.zoomedIn = zoomedIn }
    }

    func setSoundEnabled(_ enabled: Bool) {
        input.withLock { $0.soundEnabled = enabled }
    }

    func setAutoFire(_ autoFire: Bool) {
        input.withLock { $0.autoFire = autoFire }
    }

    func trigger(_ animation: RaccoonAnimation) {
        input.withLock { $0.triggers.append(animation) }
    }

    func reset() {
        input.withLock { $0.resetRequested = true }
    }

    // MARK: Bucle

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Tope de 1/20 s para que una pausa larga no teletransporte al mapache.
        let dt = min(time - (lastTime ?? time), 0.05)
        lastTime = time
        measureFPS(at: time)
        step(dt: dt)
    }

    /// Media de fotogramas en ventanas de medio segundo, para que el número no baile.
    private func measureFPS(at time: TimeInterval) {
        guard let start = fpsWindowStart else {
            fpsWindowStart = time
            return
        }
        fpsFrames += 1
        let elapsed = time - start
        if elapsed >= 0.5 {
            fps = Int((Double(fpsFrames) / elapsed).rounded())
            fpsFrames = 0
            fpsWindowStart = time
        }
    }

    /// Avanza la simulación `dt` segundos. Los tests la llaman directamente, sin vista.
    func step(dt: TimeInterval) {
        let frame = input.withLock { input in
            let copy = input
            input.triggers.removeAll()
            input.resetRequested = false
            return copy
        }

        if frame.resetRequested { simulation.reset() }
        for animation in frame.triggers { simulation.trigger(animation) }
        simulation.step(dt: dt, stick: frame.stick, aimTarget: frame.aimsAtTarget ? map.target : nil,
                        firing: frame.autoFire, map: map)
        character.apply(simulation)
        playSounds(enabled: frame.soundEnabled)

        // La cámara sigue al mapache con un poco de retardo.
        let blend = Float(min(dt * 6, 1))
        cameraOffset += ((frame.zoomedIn ? Self.nearCamera : Self.farCamera) - cameraOffset) * blend
        let focus = character.node.simdPosition + Self.lookHeight
        cameraNode.simdPosition += (focus + cameraOffset - cameraNode.simdPosition) * blend
        cameraNode.simdLook(at: cameraNode.simdPosition - cameraOffset)

        publishHUD(dt: dt)
    }

    private func playSounds(enabled: Bool) {
        audio.isEnabled = enabled
        if simulation.footstepSerial != soundedFootstep {
            soundedFootstep = simulation.footstepSerial
            audio.play(.footstep)
        }
        if simulation.shotSerial != soundedShot {
            soundedShot = simulation.shotSerial
            audio.play(.shot)
        }
        if simulation.animationSerial != soundedAnimation {
            soundedAnimation = simulation.animationSerial
            // Al cambiar de animación se corta lo que quedara de la recarga o la victoria.
            audio.stopLongSound()
            if let sound = RaccoonSound(startOf: simulation.animation) {
                audio.play(sound)
            }
        }
    }

    private func publishHUD(dt: TimeInterval) {
        hudCooldown -= dt
        let hud = HUD(animation: simulation.animation, position: simulation.position,
                      speed: simulation.speed, isDead: simulation.isDead, fps: fps)
        guard hud != lastHUD, hudCooldown <= 0 || hud.animation != lastHUD?.animation else { return }
        lastHUD = hud
        hudCooldown = 0.1
        onHUD?(hud)
    }

    // MARK: Construcción

    private func buildMap() {
        let side = CGFloat(map.halfSize * 2)
        let floor = SCNPlane(width: side, height: side)
        let material = floor.firstMaterial!
        material.diffuse.contents = Self.gridTile()
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        // Una baldosa por metro.
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(side).scnFloat, Float(side).scnFloat, 1)
        material.diffuse.mipFilter = .linear
        let floorNode = SCNNode(geometry: floor)
        floorNode.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        scene.rootNode.addChildNode(floorNode)

        let wallColor = CGColor(red: 0.20, green: 0.22, blue: 0.26, alpha: 1)
        for (x, z, width, length) in [(0, map.halfSize, side, 0.3), (0, -map.halfSize, side, 0.3),
                                      (map.halfSize, 0, 0.3, side), (-map.halfSize, 0, 0.3, side)] as [(Float, Float, CGFloat, CGFloat)] {
            let wall = SCNNode(geometry: SCNBox(width: width, height: 0.5, length: length, chamferRadius: 0.03))
            wall.geometry?.firstMaterial?.diffuse.contents = wallColor
            wall.simdPosition = SIMD3(x, 0.25, z)
            scene.rootNode.addChildNode(wall)
        }

        for obstacle in map.obstacles {
            let geometry: SCNGeometry
            let height: Float
            let color: CGColor
            switch obstacle.kind {
            case .crate:
                height = 0.8
                geometry = SCNBox(width: 0.8, height: 0.8, length: 0.8, chamferRadius: 0.04)
                color = CGColor(red: 0.60, green: 0.42, blue: 0.22, alpha: 1)
            case .barrel:
                height = 0.7
                geometry = SCNCylinder(radius: CGFloat(obstacle.radius), height: 0.7)
                color = CGColor(red: 0.20, green: 0.45, blue: 0.55, alpha: 1)
            case .target:
                height = 0.9
                geometry = SCNCapsule(capRadius: CGFloat(obstacle.radius), height: 0.9)
                color = CGColor(red: 0.85, green: 0.20, blue: 0.18, alpha: 1)
            }
            geometry.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: geometry)
            node.simdPosition = SIMD3(obstacle.center.x, height / 2, obstacle.center.y)
            scene.rootNode.addChildNode(node)
        }

        scene.background.contents = CGColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
    }

    private func buildLights() {
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1100
        sun.castsShadow = true
        sun.shadowRadius = 4
        sun.shadowSampleCount = 8
        sun.shadowColor = CGColor(gray: 0, alpha: 0.45)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.simdEulerAngles = SIMD3(-1.05, 0.6, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 500
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // El material del mapache es PBR: sin entorno, las partes metálicas salen negras.
        scene.lightingEnvironment.contents = CGColor(gray: 0.75, alpha: 1)
        scene.lightingEnvironment.intensity = 1.2
    }

    private func buildCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 40
        camera.zNear = 0.1
        camera.zFar = 60
        cameraNode.camera = camera
        cameraNode.simdPosition = character.node.simdPosition + Self.lookHeight + cameraOffset
        cameraNode.simdLook(at: cameraNode.simdPosition - cameraOffset)
        scene.rootNode.addChildNode(cameraNode)
    }

    /// Baldosa de 1 m con borde claro, para que se note el desplazamiento.
    private static func gridTile() -> CGImage? {
        let size = 128
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.33, green: 0.36, blue: 0.38, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setStrokeColor(CGColor(red: 0.47, green: 0.50, blue: 0.52, alpha: 1))
        context.setLineWidth(4)
        context.stroke(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }
}

private extension Float {
    /// Componente de `SCNMatrix4`: `Float` en iOS, `CGFloat` en macOS.
    #if os(macOS)
    nonisolated var scnFloat: CGFloat { CGFloat(self) }
    #else
    nonisolated var scnFloat: Float { self }
    #endif
}
#endif
