//
//  SandboxView.swift
//  Rakun
//

#if canImport(SceneKit)
import SwiftUI
import SceneKit

@Observable
final class SandboxModel {
    let sandbox: SandboxScene?
    let loadError: String?
    var hud = SandboxScene.HUD()
    var aimsAtTarget = false { didSet { sandbox?.setAimsAtTarget(aimsAtTarget) } }
    var zoomedIn = false { didSet { sandbox?.setZoomedIn(zoomedIn) } }
    /// Panel de estadísticas de SceneKit: triángulos, llamadas de dibujo y reparto del tiempo.
    var showsStatistics = false
    var soundEnabled = true { didSet { sandbox?.setSoundEnabled(soundEnabled) } }

    init() {
        do {
            let sandbox = try SandboxScene()
            self.sandbox = sandbox
            loadError = nil
            sandbox.onHUD = { [weak self] hud in
                Task { @MainActor in self?.hud = hud }
            }
        } catch {
            sandbox = nil
            loadError = "No se pudo cargar el mapache: \(error)"
        }
    }
}

/// Pantalla del banco de pruebas: escena 3D, joystick y botones para lanzar cada animación.
struct SandboxView: View {
    @State private var model = SandboxModel()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        if let sandbox = model.sandbox {
            ZStack {
                SceneKitView(sandbox: sandbox, showsStatistics: model.showsStatistics)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    hud
                    gallery(sandbox)
                    Spacer()
                    HStack(alignment: .bottom) {
                        JoystickView { sandbox.setStick($0) }
                        Spacer()
                        actions(sandbox)
                    }
                }
                .padding()
            }
        } else {
            Text(model.loadError ?? "Error desconocido")
                .padding()
        }
    }

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(model.hud.animation.rawValue)
                        .accessibilityIdentifier("hud.animation")
                    Text("\(model.hud.fps) fps")
                        .foregroundStyle(fpsColor)
                        .accessibilityIdentifier("hud.fps")
                }
                .font(.headline.monospaced())
                Text(String(format: "x %.1f  z %.1f  ·  %.2f m/s",
                            model.hud.position.x, model.hud.position.y, model.hud.speed))
                    .font(.caption.monospaced())
            }
            Spacer()
            // En horizontal no sobra altura: los conmutadores van en fila.
            let toggles = verticalSizeClass == .compact
                ? AnyLayout(HStackLayout(spacing: 6))
                : AnyLayout(VStackLayout(alignment: .trailing, spacing: 6))
            toggles {
                Toggle("Apuntar", isOn: $model.aimsAtTarget)
                Toggle("Zoom", isOn: $model.zoomedIn)
                Toggle("Stats", isOn: $model.showsStatistics)
                Toggle("Sonido", isOn: $model.soundEnabled)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.45), in: .rect(cornerRadius: 12))
    }

    private var fpsColor: Color {
        switch model.hud.fps {
        case 55...: .green
        case 30...: .yellow
        default: .red
        }
    }

    /// Todas las animaciones, para verlas una a una sin depender del movimiento.
    private func gallery(_ sandbox: SandboxScene) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], spacing: 6) {
            ForEach(RaccoonAnimation.allCases) { animation in
                Button { sandbox.trigger(animation) } label: {
                    Text(animation.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("gallery.\(animation.rawValue)")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.black.opacity(0.55))
        .font(.caption)
    }

    private func actions(_ sandbox: SandboxScene) -> some View {
        VStack(alignment: .trailing) {
            Button("Reiniciar") { sandbox.reset() }
                .tint(.gray)
            Button("Daño") { sandbox.trigger(.hit) }
                .tint(.orange)
            Button("Recargar") { sandbox.trigger(.reload) }
                .tint(.blue)
            Button("Disparar") { sandbox.trigger(.fire) }
                .tint(.red)
                .controlSize(.large)
        }
        .buttonStyle(.borderedProminent)
    }
}

struct JoystickView: View {
    /// x a la derecha, y hacia arriba, magnitud 0…1.
    var onChange: (SIMD2<Float>) -> Void

    @State private var knob = CGSize.zero
    private let radius: CGFloat = 60

    var body: some View {
        Circle()
            .fill(.black.opacity(0.35))
            .stroke(.white.opacity(0.5), lineWidth: 2)
            .frame(width: radius * 2, height: radius * 2)
            .overlay {
                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(width: 52, height: 52)
                    .offset(knob)
            }
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let length = max(hypot(value.translation.width, value.translation.height), 1)
                        let scale = min(length, radius) / length
                        knob = CGSize(width: value.translation.width * scale, height: value.translation.height * scale)
                        onChange(SIMD2(Float(knob.width / radius), Float(-knob.height / radius)))
                    }
                    .onEnded { _ in
                        knob = .zero
                        onChange(.zero)
                    }
            )
            .accessibilityIdentifier("joystick")
    }
}

#if os(macOS)
private typealias PlatformViewRepresentable = NSViewRepresentable
#else
private typealias PlatformViewRepresentable = UIViewRepresentable
#endif

private struct SceneKitView: PlatformViewRepresentable {
    let sandbox: SandboxScene
    var showsStatistics: Bool

    private func makeView() -> SCNView {
        let view = SCNView()
        view.scene = sandbox.scene
        view.pointOfView = sandbox.cameraNode
        view.delegate = sandbox
        view.isPlaying = true
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X
        return view
    }

    #if os(macOS)
    func makeNSView(context: Context) -> SCNView { makeView() }
    func updateNSView(_ view: SCNView, context: Context) { view.showsStatistics = showsStatistics }
    #else
    func makeUIView(context: Context) -> SCNView { makeView() }
    func updateUIView(_ view: SCNView, context: Context) { view.showsStatistics = showsStatistics }
    #endif
}

#Preview {
    SandboxView()
}
#endif
