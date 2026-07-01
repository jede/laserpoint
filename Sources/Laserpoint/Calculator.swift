import AppKit
import Expression

/// One calculator action surfaced when the query parses as a math expression.
/// The three kinds share the same evaluated `expression`/`answer`; they differ
/// only in what committing the row does.
struct CalcResult: Identifiable, Hashable {
    enum Kind: Hashable {
        case copyAnswer         // copy the result — shown first, with the answer as its title
        case copyExpression     // copy the typed expression verbatim
        case openInCalculator   // hand off to Calculator.app
    }

    let kind: Kind
    let expression: String
    let answer: String

    var id: String { "calc.\(kind).\(expression)" }

    /// The primary line: the answer leads (so it's readable at a glance), the
    /// other rows describe their action.
    var title: String {
        switch kind {
        case .copyAnswer:       return answer
        case .copyExpression:   return "Copy \(expression)"
        case .openInCalculator: return "Open in Calculator"
        }
    }

    var subtitle: String {
        switch kind {
        case .copyAnswer:       return "Copy answer  ·  \(expression)"
        case .copyExpression:   return "Copy expression"
        case .openInCalculator: return "\(expression) = \(answer)"
        }
    }

    var systemImage: String {
        switch kind {
        case .copyAnswer:       return "equal.circle.fill"
        case .copyExpression:   return "textformat.123"
        case .openInCalculator: return "function"
        }
    }
}

/// Evaluates a query as an arithmetic expression via nicklockwood/Expression.
enum Calculator {
    /// Returns the three calculator actions when `query` evaluates to a finite
    /// number, or an empty array when it isn't a math expression.
    static func actions(for query: String) -> [CalcResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard looksLikeExpression(trimmed),
              let value = try? Expression(trimmed).evaluate(),
              value.isFinite
        else { return [] }

        let answer = format(value)
        return [
            CalcResult(kind: .copyAnswer, expression: trimmed, answer: answer),
            CalcResult(kind: .copyExpression, expression: trimmed, answer: answer),
            CalcResult(kind: .openInCalculator, expression: trimmed, answer: answer),
        ]
    }

    /// True when the query is itself a valid arithmetic expression — including a
    /// bare number like "1". Used to hold off auto-launching an app while the
    /// user may still be typing math (e.g. "1" on the way to "1+1", which would
    /// otherwise instantly launch a single digit-matching app like 1Password).
    static func isExpression(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.rangeOfCharacter(from: .decimalDigits) != nil,
              let value = try? Expression(trimmed).evaluate()
        else { return false }
        return value.isFinite
    }

    /// Cheap gate so plain app names and bare numbers don't sprout calculator
    /// rows: we only treat a query as math when it has a digit *and* an operator
    /// or grouping/function parenthesis.
    private static func looksLikeExpression(_ s: String) -> Bool {
        guard s.rangeOfCharacter(from: .decimalDigits) != nil else { return false }
        return s.contains(where: { "+-*/^%(".contains($0) })
    }

    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = false
        return formatter.string(from: value as NSNumber) ?? String(value)
    }
}

/// A row in the launcher: a prefix shortcut, a calculator action, or an app.
enum SearchResult: Identifiable, Hashable {
    case shortcut(QueryShortcut)
    case calc(CalcResult)
    case app(AppEntry)

    var id: String {
        switch self {
        case .shortcut(let shortcut): return shortcut.id
        case .calc(let calc):         return calc.id
        case .app(let app):           return app.id
        }
    }
}
