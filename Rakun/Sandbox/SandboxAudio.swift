//
//  SandboxAudio.swift
//  Rakun
//

#if canImport(SceneKit)
import SceneKit

/// Reproduce los efectos del mapache y el ambiente de fondo con el motor de audio de SceneKit.
/// Se usa desde el hilo de render, igual que el resto de la escena.
nonisolated final class SandboxAudio {
    /// Nodo del que cuelgan los sonidos. No son posicionales, así que da igual dónde esté.
    let node = SCNNode()
    /// Veces que se ha pedido cada sonido con el audio activado (para los tests).
    private(set) var playCounts: [RaccoonSound: Int] = [:]

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                startLoops()
            } else {
                node.removeAllActions()
                node.removeAllAudioPlayers()
            }
        }
    }

    private var sources: [RaccoonSound: [SCNAudioSource]] = [:]
    private var lastVariant: [RaccoonSound: Int] = [:]
    /// Fondo que suena siempre en bucle: el mar junto al faro y la música de la partida.
    private var loops: [SCNAudioSource] = []

    private static let longSoundKey = "long"
    static let loopFiles: [(name: String, volume: Float)] = [
        ("ambience_sea", 0.18),
        ("music_lighthouse", 0.12),
    ]

    init(bundle: Bundle = .main) {
        for sound in RaccoonSound.allCases {
            sources[sound] = sound.fileNames.compactMap {
                Self.source(named: $0, volume: sound.volume, bundle: bundle)
            }
        }
        loops = Self.loopFiles.compactMap { Self.source(named: $0.name, volume: $0.volume, bundle: bundle) }
        for loop in loops { loop.loops = true }
        startLoops()
    }

    func play(_ sound: RaccoonSound) {
        guard isEnabled, let variants = sources[sound], !variants.isEmpty else { return }
        playCounts[sound, default: 0] += 1

        // Nunca la misma toma dos veces seguidas.
        var index = Int.random(in: 0..<variants.count)
        if variants.count > 1, index == lastVariant[sound] {
            index = (index + 1) % variants.count
        }
        lastVariant[sound] = index

        if sound.isLong {
            // Con la misma clave, el sonido largo nuevo sustituye al anterior.
            node.runAction(.playAudio(variants[index], waitForCompletion: true), forKey: Self.longSoundKey)
        } else {
            node.runAction(.playAudio(variants[index], waitForCompletion: false))
        }
    }

    /// Corta la recarga, la muerte o la victoria si estaban sonando.
    func stopLongSound() {
        node.removeAction(forKey: Self.longSoundKey)
    }

    private func startLoops() {
        for loop in loops {
            node.addAudioPlayer(SCNAudioPlayer(source: loop))
        }
    }

    private static func source(named name: String, volume: Float, bundle: Bundle) -> SCNAudioSource? {
        guard let url = bundle.url(forResource: name, withExtension: "wav"),
              let source = SCNAudioSource(url: url) else { return nil }
        source.isPositional = false
        source.volume = volume
        source.load()
        return source
    }
}
#endif
