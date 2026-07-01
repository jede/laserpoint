import XCTest
@testable import Laserpoint

final class CalculatorTests: XCTestCase {
    func testEvaluatesExpressionIntoThreeActions() {
        let actions = Calculator.actions(for: "12*8+4")
        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions.map(\.kind), [.copyAnswer, .copyExpression, .openInCalculator])
        XCTAssertEqual(actions.first?.answer, "100")
        XCTAssertEqual(actions.first?.expression, "12*8+4")
    }

    func testHandlesParenthesesAndFunctions() {
        XCTAssertEqual(Calculator.actions(for: "(1+2)*3").first?.answer, "9")
        XCTAssertEqual(Calculator.actions(for: "sqrt(9)").first?.answer, "3")
    }

    func testWhitespaceIsIgnored() {
        XCTAssertEqual(Calculator.actions(for: "  2 + 2  ").first?.answer, "4")
    }

    func testPlainNamesAndBareNumbersProduceNoActions() {
        // No operator/paren -> not treated as a calculation.
        XCTAssertTrue(Calculator.actions(for: "Safari").isEmpty)
        XCTAssertTrue(Calculator.actions(for: "42").isEmpty)
        XCTAssertTrue(Calculator.actions(for: "1password").isEmpty)
    }

    func testInvalidExpressionProducesNoActions() {
        XCTAssertTrue(Calculator.actions(for: "2 +").isEmpty)
        XCTAssertTrue(Calculator.actions(for: "1/0").isEmpty) // non-finite
    }

    func testIsExpressionSuppressesAutoLaunchForMathLikeQueries() {
        // Valid expressions (including bare numbers) should suppress auto-launch.
        for query in ["1", "42", "1+1", "2*3", "sqrt(9)", "(1+2)"] {
            XCTAssertTrue(Calculator.isExpression(query), "\(query) should be an expression")
        }
        // App-name queries should not.
        for query in ["1password", "safari", "x", "notes"] {
            XCTAssertFalse(Calculator.isExpression(query), "\(query) should not be an expression")
        }
    }
}
