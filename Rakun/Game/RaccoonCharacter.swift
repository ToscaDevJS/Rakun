//
//  RaccoonCharacter.swift
//  Rakun
//

#if canImport(SceneKit)
import SceneKit

/// El mapache en SceneKit: carga el modelo una vez y le añade las animaciones de los demás USDZ.
nonisolated final class RaccoonCharacter {
    nonisolated enum LoadError: Error {
        case missingResource(String)
        case missingAnimation(String)
    }

    /// Nodo que mueve el juego: origen en los pies, mira hacia +Z.
    let node = SCNNode()
    private(set) var players: [RaccoonAnimation: SCNAnimationPlayer] = [:]
    private(set) var current: RaccoonAnimation?
    private var appliedSerial: Int?

    static let blendDuration: TimeInterval = 0.15

    init(bundle: Bundle = .main) throws {
        let model = try Self.loadScene("raccoon", bundle: bundle)
        guard let rig = Self.animatedNode(in: model.rootNode) else {
            throw LoadError.missingAnimation("raccoon")
        }
        // El modelo trae su propio idle; se sustituye por los reproductores con nombre.
        rig.removeAllAnimations()

        for animation in RaccoonAnimation.allCases {
            // Todos los archivos comparten jerarquía, así que la animación de uno vale para el otro.
            let source = try Self.loadScene(animation.resourceName, bundle: bundle)
            guard let sourceRig = Self.animatedNode(in: source.rootNode),
                  let key = sourceRig.animationKeys.first,
                  let sourcePlayer = sourceRig.animationPlayer(forKey: key) else {
                throw LoadError.missingAnimation(animation.resourceName)
            }
            let clip = sourcePlayer.animation
            clip.repeatCount = animation.loops ? .greatestFiniteMagnitude : 1
            clip.blendInDuration = Self.blendDuration
            clip.blendOutDuration = Self.blendDuration
            // Las acciones se quedan en el último fotograma hasta que entra la siguiente animación;
            // si no, el esqueleto vuelve un instante a la T-pose.
            clip.isRemovedOnCompletion = animation.loops
            clip.fillsForward = !animation.loops

            let player = SCNAnimationPlayer(animation: clip)
            rig.addAnimationPlayer(player, forKey: animation.rawValue)
            player.stop()
            players[animation] = player
        }

        for child in model.rootNode.childNodes {
            node.addChildNode(child)
        }
        play(.idle)
    }

    func play(_ animation: RaccoonAnimation) {
        guard let next = players[animation] else { return }
        if let current, current != animation {
            players[current]?.stop(withBlendOutDuration: Self.blendDuration)
        } else {
            next.stop()
        }
        next.play()
        current = animation
    }

    /// Coloca el nodo y lanza la animación que pide la simulación.
    func apply(_ simulation: RaccoonSimulation) {
        node.simdPosition = SIMD3(simulation.position.x, 0, simulation.position.y)
        node.simdEulerAngles = SIMD3(0, simulation.yaw, 0)
        if appliedSerial != simulation.animationSerial {
            appliedSerial = simulation.animationSerial
            play(simulation.animation)
        }
    }

    private static func loadScene(_ name: String, bundle: Bundle) throws -> SCNScene {
        guard let url = bundle.url(forResource: name, withExtension: "usdz") else {
            throw LoadError.missingResource(name)
        }
        return try SCNScene(url: url, options: nil)
    }

    private static func animatedNode(in root: SCNNode) -> SCNNode? {
        var found: SCNNode?
        root.enumerateHierarchy { node, stop in
            if !node.animationKeys.isEmpty {
                found = node
                stop.pointee = true
            }
        }
        return found
    }
}
#endif
