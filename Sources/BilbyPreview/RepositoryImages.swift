import BilbyCore
import BilbyUI
import SwiftUI

/// The same Spanish examples feed both the app previews and repository art,
/// so regenerating one cannot silently bring back a different language.
@MainActor
enum PreviewCaptions {
    static let source = "Let’s make sure everyone can follow the conversation."
    static let translation = "Asegurémonos de que todos puedan seguir la conversación."

    static func caption() -> CaptionModel {
        translated([(source, translation)])
    }

    static func history() -> CaptionModel {
        let model = translated([
            (
                "So let's circle back on the runway before we commit to Q3.",
                "Volvamos a revisar cuánto nos durará la caja antes de comprometernos para el tercer trimestre."
            ),
            (
                "Burn is up eighteen percent quarter over quarter.",
                "El consumo de caja aumentó un dieciocho por ciento respecto al trimestre anterior."
            ),
            ("Two senior hires are pending offer.", "Falta enviar las ofertas a dos candidatos sénior."),
        ])
        model.apply(.live("And the bridge round term sheet"))
        model.apply(.draft("Y la hoja de términos de la ronda puente"))
        return model
    }

    private static func translated(_ lines: [(String, String)]) -> CaptionModel {
        let model = CaptionModel()
        var engine = CaptionEngine()
        for (source, translation) in lines {
            for event in engine.consume(Utterance(source, isFinal: true)) { model.apply(event) }
            if let line = model.latest {
                for event in engine.resolve(line.id, translation: translation) { model.apply(event) }
            }
        }
        return model
    }
}

/// Repository images are renders of the real caption views and app icon.
/// Keep their framing here so the next text change is reproducible too.
@MainActor
enum RepositoryImages {
    static func write(to directory: URL) throws {
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            let hero = CaptionBar(model: PreviewCaptions.caption(), perform: { _ in })
                .frame(width: 860)
                .offset(y: 7)
                .frame(width: 980, height: 239)
                .background(backdrop(scheme))
                .environment(\.colorScheme, scheme)
            try Preview.save(hero, to: directory.appendingPathComponent("hero-\(appearance).png"))

            let history = HistoryView(model: PreviewCaptions.history(), perform: { _ in })
                .frame(width: 380, height: 520)
                .environment(\.colorScheme, scheme)
            try Preview.save(history, to: directory.appendingPathComponent("history-\(appearance).png"))
        }

        let social = VStack(spacing: 34) {
            HStack(spacing: 26) {
                Image(nsImage: Icon.image(side: 150))
                    .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bilby")
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                    Text("Live captions and translation for any audio on your Mac")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            CaptionBar(model: PreviewCaptions.caption(), perform: { _ in })
                .frame(width: 980)
        }
        .frame(width: 1280, height: 640)
        .background(backdrop(.dark))
        .environment(\.colorScheme, .dark)
        try Preview.save(social, to: directory.appendingPathComponent("social-preview.png"))
    }

    private static func backdrop(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .light
                ? [Color(red: 0.90, green: 0.92, blue: 0.97), Color(red: 0.96, green: 0.95, blue: 0.93)]
                : [Color(red: 0.18, green: 0.19, blue: 0.30), Color(red: 0.05, green: 0.05, blue: 0.09)],
            startPoint: .top, endPoint: .bottom)
    }
}
