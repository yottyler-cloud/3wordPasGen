import SwiftUI
import UIKit

/// パスワード生成画面。
/// 旧版 / 最新版をトグルで切り替え、文字数を選び、記号あり / なしを同時に生成します。
/// パスワードは伏せ字（●）で表示し、目のマークで表示を切り替えます。
struct ContentView: View {
    @State private var scheme: PasswordScheme = .latest
    @State private var keywords: [String] = ["", "", ""]
    @State private var length: Int = 12
    @State private var pwSymbols = ""
    @State private var pwNoSymbols = ""
    @State private var showSymbols = false
    @State private var showNoSymbols = false
    @State private var hasGenerated = false
    @State private var status = ""
    @State private var compatibilityOK = true

    private let lengths = [8, 12, 16, 20]

    var body: some View {
        NavigationStack {
            Form {
                if !compatibilityOK {
                    Section {
                        Text("⚠️ Python 版と同じ結果になりません。この端末で生成したパスワードは使わないでください。")
                            .foregroundStyle(.red)
                    }
                }

                // --- バージョン切り替え ---
                Section {
                    Picker("方式", selection: $scheme) {
                        ForEach(PasswordScheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("方式")
                } footer: {
                    Text("最新版＝大文字・小文字・数字を必ず含む方式。旧版＝最初のバージョン。同じキーワードでも結果が変わります。")
                }

                // --- キーワード入力 ---
                Section {
                    ForEach(0..<3, id: \.self) { i in
                        TextField("キーワード\(i + 1)", text: $keywords[i])
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.default)
                            .submitLabel(i < 2 ? .next : .done)
                    }
                    Button("キーワード一括コピー", action: copyKeywords)
                } header: {
                    Text("キーワード")
                }

                // --- 文字数 ---
                Section {
                    Picker("文字数", selection: $length) {
                        ForEach(lengths, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("文字数")
                }

                // --- 生成 / リセット ---
                Section {
                    Button(action: generatePasswords) {
                        Text("生成").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive, action: resetFields) {
                        Text("リセット").frame(maxWidth: .infinity)
                    }
                }

                // --- 結果 ---
                Section {
                    resultRow(label: "記号あり", password: pwSymbols, show: $showSymbols)
                    resultRow(label: "記号なし", password: pwNoSymbols, show: $showNoSymbols)
                } footer: {
                    Text("数字は青、小文字は赤で表示します。目のマークで表示 / 伏せ字を切り替えます。")
                }

                if !status.isEmpty {
                    Section { Text(status).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("パスワード生成")
        }
        .onAppear { compatibilityOK = PasswordGenerator.passesCompatibilityCheck() }
        .onChange(of: scheme) { if hasGenerated { generatePasswords() } }
        .onChange(of: length) { if hasGenerated { generatePasswords() } }
    }

    // MARK: - 結果の行

    @ViewBuilder
    private func resultRow(label: String, password: String, show: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Button {
                    show.wrappedValue.toggle()
                } label: {
                    Image(systemName: show.wrappedValue ? "eye.slash" : "eye")
                        .accessibilityLabel(show.wrappedValue ? "パスワードを隠す" : "パスワードを表示")
                }
                .buttonStyle(.borderless)
                .disabled(password.isEmpty)

                Button("コピー") { copyPassword(password, label: label) }
                    .buttonStyle(.borderless)
            }
            Group {
                if password.isEmpty {
                    Text(" ")
                } else if show.wrappedValue {
                    coloredPassword(password)
                } else {
                    Text(String(repeating: "●", count: password.count)).foregroundStyle(.secondary)
                }
            }
            .font(.system(.title3, design: .monospaced))
            .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    /// 数字を青、小文字を赤、それ以外を通常色で表示する（Python 版と同じ色分け）
    private func coloredPassword(_ pw: String) -> Text {
        pw.reduce(Text("")) { acc, ch in
            acc + Text(String(ch)).foregroundColor(color(for: ch))
        }
    }

    private func color(for ch: Character) -> Color {
        if ("0"..."9").contains(ch) { return .blue }
        if ("a"..."z").contains(ch) { return .red }
        return .primary
    }

    // MARK: - 処理

    private func generatePasswords() {
        let normalized = keywords.map(PasswordGenerator.normalizeKeyword)
        do {
            pwSymbols = try PasswordGenerator.generate(scheme: scheme, keywords: normalized, useSymbols: true, length: length)
            pwNoSymbols = try PasswordGenerator.generate(scheme: scheme, keywords: normalized, useSymbols: false, length: length)
            showSymbols = false
            showNoSymbols = false
            hasGenerated = true
            status = ""
        } catch {
            status = error.localizedDescription
        }
    }

    private func copyPassword(_ password: String, label: String) {
        if password.isEmpty {
            status = "先に生成してください"
            return
        }
        UIPasteboard.general.string = password
        status = "\(label)（\(length)文字・\(scheme.title)）をコピーしました"
    }

    private func copyKeywords() {
        if keywords.allSatisfy({ $0.isEmpty }) {
            status = "先にキーワードを入力してください"
            return
        }
        UIPasteboard.general.string = keywords.joined(separator: "\n")
        status = "キーワード3つをコピーしました"
    }

    private func resetFields() {
        keywords = ["", "", ""]
        pwSymbols = ""
        pwNoSymbols = ""
        showSymbols = false
        showNoSymbols = false
        hasGenerated = false
        length = 12
        status = "リセットしました"
    }
}
