import SwiftUI

enum Block {
    case para(String)
    case heading(Int, String)
    case bullet(String)
    case number(String, String)
    case quote(String)
    case code(String, String)
    case rule
}

func rich(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}

func parseBlocks(_ text: String) -> [Block] {
    var out: [Block] = []
    var para: [String] = []
    let lines = text.components(separatedBy: "\n")
    var i = 0

    func flush() {
        if !para.isEmpty { out.append(.para(para.joined(separator: "\n"))); para = [] }
    }

    while i < lines.count {
        let line = lines[i]
        let t = line.trimmingCharacters(in: .whitespaces)

        if t.hasPrefix("```") {
            flush()
            let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var code: [String] = []
            i += 1
            while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                code.append(lines[i])
                i += 1
            }
            out.append(.code(lang, code.joined(separator: "\n")))
            i += 1
            continue
        }

        if t.isEmpty {
            flush()
        } else if t == "---" || t == "***" || t == "___" {
            flush()
            out.append(.rule)
        } else if t.hasPrefix("#") {
            let level = t.prefix(while: { $0 == "#" }).count
            let rest = t.dropFirst(level)
            if level <= 6, rest.hasPrefix(" ") {
                flush()
                out.append(.heading(level, rest.trimmingCharacters(in: .whitespaces)))
            } else {
                para.append(line)
            }
        } else if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") {
            flush()
            out.append(.bullet(String(t.dropFirst(2))))
        } else if let r = t.range(of: #"^\d+[.)] "#, options: .regularExpression) {
            flush()
            let marker = String(t[r]).trimmingCharacters(in: .whitespaces)
            out.append(.number(marker, String(t[r.upperBound...])))
        } else if t.hasPrefix("> ") {
            flush()
            out.append(.quote(String(t.dropFirst(2))))
        } else {
            para.append(line)
        }
        i += 1
    }
    flush()
    return out
}

struct CodeBlock: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.caption)
                    .foregroundColor(Theme.dim)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .foregroundColor(Theme.dim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider().background(Theme.hairline)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct BlockView: View {
    let block: Block

    var body: some View {
        switch block {
        case .para(let s):
            Text(rich(s)).lineSpacing(3).textSelection(.enabled)
        case .heading(let level, let s):
            Text(rich(s))
                .font(.system(size: level == 1 ? 22 : (level == 2 ? 19 : 17), weight: .bold))
                .padding(.top, 4)
                .textSelection(.enabled)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundColor(Theme.accent)
                Text(rich(s)).lineSpacing(3).textSelection(.enabled)
            }
        case .number(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(n).foregroundColor(Theme.accent)
                Text(rich(s)).lineSpacing(3).textSelection(.enabled)
            }
        case .quote(let s):
            HStack(spacing: 10) {
                Rectangle().fill(Theme.accent).frame(width: 3)
                Text(rich(s)).foregroundColor(Theme.dim).textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let lang, let body):
            CodeBlock(language: lang, code: body)
        case .rule:
            Divider().background(Theme.hairline)
        }
    }
}
