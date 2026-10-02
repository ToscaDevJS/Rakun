//
//  RakunTests.swift
//  RakunTests
//
//  Created by Orlando Jesus Abril Tosca on 30/09/2026.
//

import Foundation
import Testing
import simd
@testable import Rakun

private let frame: TimeInterval = 1.0 / 60

private extension RaccoonSimulation {
    /// Avanza `seconds` a 60 fps con el joystick fijo.
    mutating func run(_ seconds: TimeInterval, stick: SIMD2<Float> = .zero, aimTarget: SIMD2<Float>? = nil,
                      map: SandboxMap = .basic) {
        for _ in 0..<Int((seconds / frame).rounded()) {
            step(dt: frame, stick: stick, aimTarget: aimTarget, map: map)
        }
    }
}

/// Mapa vacío para que los obstáculos no interfieran en los tests de movimiento.
private let emptyMap = SandboxMap(halfSize: 6, obstacles: [], target: SIMD2(0, -4))

struct RaccoonSimulationTests {

    @Test func quietoSinJoystick() {
        var raccoon = RaccoonSimulation()
        raccoon.run(1, map: emptyMap)
        #expect(raccoon.animation == .idle)
        #expect(raccoon.position == .zero)
        #expect(raccoon.speed == 0)
    }

    @Test func correHaciaDondeApuntaElJoystick() {
        var raccoon = RaccoonSimulation()
        // Joystick arriba = alejarse de la cámara = -Z.
        raccoon.run(1, stick: SIMD2(0, 1), map: emptyMap)
        #expect(raccoon.animation == .run)
        #expect(abs(raccoon.position.x) < 0.01)
        #expect(abs(raccoon.position.y + raccoon.tuning.runSpeed) < 0.05)
        // Ha girado para mirar hacia donde va.
        #expect(simd_dot(raccoon.facing, SIMD2(0, -1)) > 0.99)
    }

    @Test func andaConElJoystickAMedias() {
        var raccoon = RaccoonSimulation()
        raccoon.run(1, stick: SIMD2(0.4, 0), map: emptyMap)
        #expect(raccoon.animation == .walk)
        #expect(abs(raccoon.position.x - raccoon.tuning.walkSpeed) < 0.02)
    }

    @Test func zonaMuertaDelJoystick() {
        var raccoon = RaccoonSimulation()
        raccoon.run(1, stick: SIMD2(0.1, 0.05), map: emptyMap)
        #expect(raccoon.animation == .idle)
        #expect(raccoon.position == .zero)
    }

    @Test(arguments: [
        (SIMD2<Float>(0, 1), RaccoonAnimation.run),
        (SIMD2<Float>(0, -1), RaccoonAnimation.runBackward),
        // Mirando a -Z (hacia el objetivo), la izquierda del mapache es -X: joystick a la izquierda.
        (SIMD2<Float>(-1, 0), RaccoonAnimation.strafeLeft),
        (SIMD2<Float>(1, 0), RaccoonAnimation.strafeRight),
    ])
    func apuntandoSeMueveSinDejarDeMirarAlObjetivo(stick: SIMD2<Float>, expected: RaccoonAnimation) {
        var raccoon = RaccoonSimulation()
        let target = SIMD2<Float>(0, -4)
        // Primero se deja que gire hacia el objetivo.
        raccoon.run(1, aimTarget: target, map: emptyMap)
        raccoon.run(0.5, stick: stick, aimTarget: target, map: emptyMap)
        #expect(raccoon.animation == expected)
        let toTarget = simd_normalize(target - raccoon.position)
        #expect(simd_dot(raccoon.facing, toTarget) > 0.98)
    }

    @Test func noSaleDelMapa() {
        var raccoon = RaccoonSimulation()
        raccoon.run(15, stick: SIMD2(1, 0), map: emptyMap)
        #expect(abs(raccoon.position.x - (emptyMap.halfSize - raccoon.tuning.radius)) < 0.001)
    }

    @Test func noAtraviesaObstaculos() {
        let crate = SandboxMap.Obstacle(center: SIMD2(2, 0), radius: 0.55, kind: .crate)
        let map = SandboxMap(halfSize: 6, obstacles: [crate], target: .zero)
        var raccoon = RaccoonSimulation()
        for _ in 0..<600 {
            raccoon.step(dt: frame, stick: SIMD2(1, 0), aimTarget: nil, map: map)
            let distance = simd_distance(raccoon.position, crate.center)
            #expect(distance >= crate.radius + raccoon.tuning.radius - 0.001)
        }
    }

    @Test func dispararDePieVuelveAQuietoAlTerminar() {
        var raccoon = RaccoonSimulation()
        raccoon.trigger(.fire)
        #expect(raccoon.animation == .fire)
        #expect(raccoon.shotSerial == 1)
        raccoon.run(0.2, map: emptyMap)
        #expect(raccoon.animation == .fire)
        raccoon.run(0.2, map: emptyMap)
        #expect(raccoon.animation == .idle)
    }

    /// Al disparar andando o corriendo se usa la variante en marcha, no el disparo de pie.
    @Test(arguments: [
        (SIMD2<Float>(0, 1), RaccoonAnimation.run, RaccoonAnimation.runFire),
        (SIMD2<Float>(0, 0.4), .walk, .walkFire),
    ])
    func dispararEnMarchaUsaLaVariante(stick: SIMD2<Float>, normal: RaccoonAnimation, firing: RaccoonAnimation) {
        var raccoon = RaccoonSimulation()
        raccoon.run(0.3, stick: stick, map: emptyMap)
        #expect(raccoon.animation == normal)
        let before = raccoon.position

        raccoon.trigger(.fire)
        raccoon.run(0.1, stick: stick, map: emptyMap)
        #expect(raccoon.animation == firing)
        #expect(raccoon.shotSerial == 1)
        // Disparar no frena al mapache: sigue a la velocidad del paso normal.
        #expect(raccoon.speed == (normal == .run ? raccoon.tuning.runSpeed : raccoon.tuning.walkSpeed))
        #expect(raccoon.position != before)

        // Pasada la ventana del disparo vuelve al paso normal.
        raccoon.run(1, stick: stick, map: emptyMap)
        #expect(raccoon.animation == normal)
    }

    @Test func deLadoODeEspaldasNoHayVarianteDeDisparo() {
        var raccoon = RaccoonSimulation()
        let target = SIMD2<Float>(0, -4)
        raccoon.run(1, aimTarget: target, map: emptyMap)
        raccoon.trigger(.fire)
        raccoon.run(0.1, stick: SIMD2(1, 0), aimTarget: target, map: emptyMap)
        #expect(raccoon.animation == .fire)
        raccoon.run(0.3, stick: SIMD2(1, 0), aimTarget: target, map: emptyMap)
        #expect(raccoon.animation == .strafeRight)
    }

    @Test func dosDisparosSeguidosRelanzanLaAnimacion() {
        var raccoon = RaccoonSimulation()
        raccoon.trigger(.fire)
        let first = raccoon.animationSerial
        raccoon.trigger(.fire)
        #expect(raccoon.animation == .fire)
        #expect(raccoon.animationSerial != first)
        #expect(raccoon.shotSerial == 2)
    }

    @Test func elFuegoAutomaticoDisparaACadencia() {
        var raccoon = RaccoonSimulation()
        for _ in 0..<120 {
            raccoon.step(dt: frame, stick: .zero, aimTarget: nil, firing: true, map: emptyMap)
        }
        // 2 s con un disparo cada 0,6 s: a los 0, 0,6, 1,2 y 1,8 s.
        #expect(raccoon.shotSerial == 4)
        #expect(raccoon.position == .zero)
    }

    @Test func elFuegoAutomaticoEnMarchaNoReiniciaLaAnimacion() {
        var raccoon = RaccoonSimulation()
        for _ in 0..<30 {
            raccoon.step(dt: frame, stick: SIMD2(0, 1), aimTarget: nil, firing: true, map: emptyMap)
        }
        #expect(raccoon.animation == .runFire)
        let serial = raccoon.animationSerial
        for _ in 0..<125 {
            raccoon.step(dt: frame, stick: SIMD2(0, 1), aimTarget: nil, firing: true, map: emptyMap)
        }
        // Sigue en el mismo bucle aunque haya disparado varias veces más.
        #expect(raccoon.animation == .runFire)
        #expect(raccoon.animationSerial == serial)
        #expect(raccoon.shotSerial == 5)
        // La animación va acelerada (×1,52), así que da más pasos por segundo que corriendo:
        // 8 en 2,57 s, frente a los 7 de la carrera normal.
        #expect(raccoon.footstepSerial == 8)
    }

    @Test func elFuegoAutomaticoNoInterrumpeLaRecarga() {
        var raccoon = RaccoonSimulation()
        raccoon.trigger(.reload)
        for _ in 0..<60 {
            raccoon.step(dt: frame, stick: .zero, aimTarget: nil, firing: true, map: emptyMap)
        }
        #expect(raccoon.animation == .reload)
        #expect(raccoon.shotSerial == 0)
    }

    @Test func elGolpeLoDejaClavado() {
        var raccoon = RaccoonSimulation()
        raccoon.trigger(.hit)
        raccoon.run(0.5, stick: SIMD2(0, 1), map: emptyMap)
        #expect(raccoon.animation == .hit)
        #expect(raccoon.position == .zero)
        raccoon.run(0.3, stick: SIMD2(0, 1), map: emptyMap)
        #expect(raccoon.animation == .run)
        #expect(raccoon.position.y < 0)
    }

    @Test func muertoNoSeMueveHastaReiniciar() {
        var raccoon = RaccoonSimulation()
        raccoon.trigger(.death)
        raccoon.trigger(.fire)
        raccoon.run(1, stick: SIMD2(1, 0), map: emptyMap)
        #expect(raccoon.isDead)
        #expect(raccoon.animation == .death)
        #expect(raccoon.position == .zero)

        raccoon.reset()
        raccoon.run(0.5, stick: SIMD2(1, 0), map: emptyMap)
        #expect(!raccoon.isDead)
        #expect(raccoon.animation == .run)
    }

    /// Contactos de pie medidos en Blender: corriendo, a los 0,233 y 0,633 s de cada ciclo.
    @Test func losPasosSiguenALosPiesAlCorrer() {
        var raccoon = RaccoonSimulation()
        raccoon.run(0.2, stick: SIMD2(0, 1), map: emptyMap)
        #expect(raccoon.footstepSerial == 0)
        raccoon.run(0.1, stick: SIMD2(0, 1), map: emptyMap)
        #expect(raccoon.footstepSerial == 1)
        raccoon.run(0.6, stick: SIMD2(0, 1), map: emptyMap)
        #expect(raccoon.footstepSerial == 2)
        // Segunda vuelta del bucle (0,733 s por ciclo).
        raccoon.run(0.9, stick: SIMD2(0, 1), map: emptyMap)
        #expect(raccoon.footstepSerial == 5)
    }

    @Test func andandoDaMenosPasosQueCorriendo() {
        var raccoon = RaccoonSimulation()
        raccoon.run(1.3, stick: SIMD2(0.4, 0), map: emptyMap)
        #expect(raccoon.animation == .walk)
        #expect(raccoon.footstepSerial == 2)
    }

    @Test func sinMoverseNoHayPasos() {
        var raccoon = RaccoonSimulation()
        raccoon.run(2, map: emptyMap)
        raccoon.trigger(.reload)
        raccoon.run(2, map: emptyMap)
        raccoon.trigger(.death)
        raccoon.run(2, stick: SIMD2(1, 0), map: emptyMap)
        #expect(raccoon.footstepSerial == 0)
    }

    @Test func reiniciarNoPierdeLaCuentaDePasos() {
        var raccoon = RaccoonSimulation()
        raccoon.run(1, stick: SIMD2(0, 1), map: emptyMap)
        let steps = raccoon.footstepSerial
        raccoon.reset()
        #expect(raccoon.footstepSerial == steps)
    }

    @Test(arguments: [
        (RaccoonAnimation.reload, RaccoonSound.reload), (.hit, .hit), (.death, .death), (.victory, .victory),
    ])
    func cadaAccionTieneSuSonido(animation: RaccoonAnimation, sound: RaccoonSound) {
        #expect(RaccoonSound(startOf: animation) == sound)
    }

    @Test func elMovimientoNoDisparaSonidosDeAccion() {
        for animation in RaccoonAnimation.allCases where animation.loops && animation != .victory {
            #expect(RaccoonSound(startOf: animation) == nil)
        }
        // El disparo suena por `shotSerial`, no por el arranque de la animación.
        #expect(RaccoonSound(startOf: .fire) == nil)
    }

    @Test func laVistaPreviaSeCancelaAlMoverse() {
        var raccoon = RaccoonSimulation()
        raccoon.trigger(.victory)
        raccoon.run(2, map: emptyMap)
        #expect(raccoon.animation == .victory)
        raccoon.run(0.2, stick: SIMD2(0, 1), map: emptyMap)
        #expect(raccoon.animation == .run)
        raccoon.run(0.2, map: emptyMap)
        #expect(raccoon.animation == .idle)
    }
}

#if canImport(SceneKit)
import SceneKit

/// Comprueban los USDZ reales del bundle de la app con SceneKit.
struct RaccoonAssetTests {

    @Test func cargaTodasLasAnimaciones() throws {
        let raccoon = try RaccoonCharacter()
        #expect(raccoon.players.count == RaccoonAnimation.allCases.count)
        #expect(raccoon.players.count == 13)
        #expect(raccoon.current == .idle)
        // Correr disparando va acelerada para casar con la velocidad de carrera.
        // SceneKit guarda la velocidad con precisión simple: se compara con margen.
        let runFireSpeed = try #require(raccoon.players[.runFire]).speed
        #expect(abs(runFireSpeed - 1.52) < 0.001)
        #expect(raccoon.players[.run]?.speed == 1)
    }

    /// Duraciones de `game-assets/README.md`. Los laterales van cruzados: el archivo
    /// `strafe_left` (0,67 s) se desplaza hacia la derecha del mapache y viceversa.
    @Test(arguments: [
        (RaccoonAnimation.idle, 3.1), (.run, 0.73), (.walk, 1.37), (.strafeLeft, 0.53),
        (.strafeRight, 0.67), (.runBackward, 0.53), (.walkFire, 1.33), (.runFire, 0.93),
        (.fire, 0.27), (.reload, 3.3), (.hit, 2.3), (.death, 3.07), (.victory, 17.3),
    ])
    func duracionDeCadaAnimacion(animation: RaccoonAnimation, seconds: Double) throws {
        let raccoon = try RaccoonCharacter()
        let clip = try #require(raccoon.players[animation]).animation
        #expect(abs(clip.duration - seconds) < 0.05)
        #expect((clip.repeatCount > 1) == animation.loops)
    }

    @Test func elModeloTieneMallaConEsqueleto() throws {
        let raccoon = try RaccoonCharacter()
        var bones = 0
        raccoon.node.enumerateHierarchy { node, _ in
            bones = max(bones, node.skinner?.bones.count ?? 0)
        }
        #expect(bones == 57)
    }
}

struct RaccoonAudioTests {

    @Test(arguments: RaccoonSound.allCases)
    func estanTodosLosArchivosDeSonido(sound: RaccoonSound) {
        for name in sound.fileNames {
            #expect(Bundle.main.url(forResource: name, withExtension: "wav") != nil, "falta \(name).wav")
        }
    }

    @Test func estanElAmbienteYLaMusica() {
        for loop in SandboxAudio.loopFiles {
            #expect(Bundle.main.url(forResource: loop.name, withExtension: "wav") != nil, "falta \(loop.name).wav")
        }
    }

    @Test func correrSuenaAPasosYDispararADisparo() throws {
        let sandbox = try SandboxScene()
        sandbox.setStick(SIMD2(0, 1))
        for _ in 0..<60 { sandbox.step(dt: frame) }
        // 0,233 y 0,633 s del primer ciclo y 0,967 s del segundo.
        #expect(sandbox.audio.playCounts[.footstep] == 3)

        sandbox.trigger(.fire)
        sandbox.step(dt: frame)
        sandbox.trigger(.fire)
        sandbox.step(dt: frame)
        #expect(sandbox.audio.playCounts[.shot] == 2)
        #expect(sandbox.audio.playCounts[.reload] == nil)
    }

    @Test func elFuegoAutomaticoSuenaACadaDisparo() throws {
        let sandbox = try SandboxScene()
        sandbox.setAutoFire(true)
        sandbox.setStick(SIMD2(0, 1))
        for _ in 0..<120 { sandbox.step(dt: frame) }
        #expect(sandbox.character.current == .runFire)
        #expect(sandbox.audio.playCounts[.shot] == 4)

        sandbox.setAutoFire(false)
        for _ in 0..<90 { sandbox.step(dt: frame) }
        #expect(sandbox.character.current == .run)
        #expect(sandbox.audio.playCounts[.shot] == 4)
    }

    @Test func enSilencioNoSuenaNada() throws {
        let sandbox = try SandboxScene()
        sandbox.setSoundEnabled(false)
        sandbox.setStick(SIMD2(0, 1))
        sandbox.trigger(.hit)
        for _ in 0..<120 { sandbox.step(dt: frame) }
        #expect(sandbox.audio.playCounts.isEmpty)
    }
}

struct SandboxSceneTests {

    @Test func elJoystickMueveElNodoYCambiaLaAnimacion() throws {
        let sandbox = try SandboxScene()
        sandbox.setStick(SIMD2(1, 0))
        for _ in 0..<60 { sandbox.step(dt: frame) }
        #expect(sandbox.character.current == .run)
        #expect(sandbox.character.node.simdPosition.x > 1)
        // Origen en los pies: el nodo no se despega del suelo.
        #expect(sandbox.character.node.simdPosition.y == 0)

        sandbox.setStick(.zero)
        sandbox.step(dt: frame)
        #expect(sandbox.character.current == .idle)
    }

    @Test func lasOrdenesDeLaInterfazLleganAlPersonaje() throws {
        let sandbox = try SandboxScene()
        sandbox.trigger(.reload)
        sandbox.step(dt: frame)
        #expect(sandbox.character.current == .reload)

        sandbox.trigger(.death)
        sandbox.step(dt: frame)
        #expect(sandbox.simulation.isDead)

        sandbox.reset()
        sandbox.step(dt: frame)
        #expect(sandbox.character.current == .idle)
        #expect(!sandbox.simulation.isDead)
    }

    @Test func laCamaraSigueAlMapache() throws {
        let sandbox = try SandboxScene()
        let start = sandbox.cameraNode.simdPosition
        sandbox.setStick(SIMD2(1, 0))
        for _ in 0..<180 { sandbox.step(dt: frame) }
        let moved = sandbox.cameraNode.simdPosition.x - start.x
        #expect(abs(moved - sandbox.character.node.simdPosition.x) < 0.3)
    }
}
#endif
