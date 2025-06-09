import Defaults
import SwiftUI

struct LanguagePicker: View {
    @State private var languageManager = LanguageManager.shared
    @State private var showingRestartAlert = false

    var body: some View {
        Picker("", selection: $languageManager.currentLanguage) {
            ForEach(LanguageManager.supportedLanguages) { language in
                Text(language.nativeName)
                    .tag(language)
            }
        }
        .labelsHidden()
        .frame(width: 180)
        .onChange(of: languageManager.currentLanguage) { _, newLanguage in
            if newLanguage != .system
                && newLanguage
                    != AppLanguage(
                        rawValue: Locale.current.language.languageCode?.identifier ?? "en") {
                showingRestartAlert = true
            }
        }
        .alert("Language Changed", isPresented: $showingRestartAlert) {
            Button("Restart Later") {}
            Button("Restart Now") {
                restartApplication()
            }
        } message: {
            Text("The language change will take effect after restarting the application.")
        }
    }

    private func restartApplication() {
        // Save current language setting
        languageManager.applyLanguage()

        // Get the current executable URL
        let url = URL(fileURLWithPath: Bundle.main.executablePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()

        // Quit current instance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}

#Preview {
    LanguagePicker()
        .environment(\.locale, .init(identifier: "en"))
}
