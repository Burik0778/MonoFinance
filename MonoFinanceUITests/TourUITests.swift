import XCTest

/// Автоматическая «экскурсия» по приложению на демо-данных: используется для записи видео в CI
/// и заодно проверяет, что основные экраны открываются без падений.
final class TourUITests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-monoScreenshots", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
    }

    func testTour() {
        app.launch()
        wait(3.5)

        // Обзор: прокрутка вниз и обратно.
        for _ in 0..<3 {
            app.swipeUp(velocity: .slow)
            wait(1.4)
        }
        for _ in 0..<3 { app.swipeDown(velocity: .fast) }
        wait(1)

        // Скрыть и показать суммы.
        tap(button("Скрыть суммы"))
        wait(1.2)
        tap(button("Показать суммы"))
        wait(1)

        // Голосовой ввод: сфера, затем ввод фразы текстом (в симуляторе нет микрофона).
        tap(button("Голосовой ввод операции"))
        wait(1.5)
        allowSystemAlerts()
        // В симуляторе русская речь распознаётся только серверами Apple — даём согласие, чтобы показать запись.
        if button("Разрешить серверы Apple").waitForExistence(timeout: 2) {
            tap(button("Разрешить серверы Apple"))
            wait(1)
            allowSystemAlerts()
        }
        wait(3)
        tap(button("Ввести текстом"))
        wait(1)
        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        if field.waitForExistence(timeout: 3) {
            field.tap()
            field.typeText("Вчера купил продукты в Корзинке на 245 тысяч и потратил 40 тысяч на такси")
            wait(1)
        }
        tap(button("Разобрать фразу"))
        wait(3)
        app.swipeUp(velocity: .slow)
        wait(1.5)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Сохранить'")).firstMatch)
        wait(2.5)
        // Если лист голосового ввода всё ещё открыт — закрываем, чтобы продолжить экскурсию.
        if button("Закрыть").exists { tap(button("Закрыть")) }
        wait(1)

        // Операции: список и карточка операции.
        tap(button("Операции"))
        wait(2)
        app.swipeUp(velocity: .slow)
        wait(1.5)
        app.swipeDown(velocity: .fast)
        wait(1)
        let firstRow = app.cells.element(boundBy: 2)
        if firstRow.waitForExistence(timeout: 2) {
            firstRow.tap()
            wait(2.5)
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            wait(1)
        }

        // Аналитика.
        tap(button("Аналитика"))
        wait(2.5)
        for _ in 0..<4 {
            app.swipeUp(velocity: .slow)
            wait(1.8)
        }
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        wait(1)

        // Планы.
        tap(button("Планы"))
        wait(2.5)
        app.swipeUp(velocity: .slow)
        wait(2)
        app.swipeUp(velocity: .slow)
        wait(1.5)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        wait(1)

        // Новый расход с цифровой клавиатуры.
        tap(button("Обзор"))
        wait(1.5)
        tap(button("Расход"))
        wait(1.5)
        for digit in ["1", "5", "0", "0", "0", "0"] {
            tap(button(digit), timeout: 2)
            wait(0.25)
        }
        wait(0.8)
        tap(button("Такси"), timeout: 2)
        wait(1)
        tap(button("Сохранить"), timeout: 2)
        wait(2.5)

        // Настройки.
        tap(button("Настройки"))
        wait(2)
        app.swipeUp(velocity: .slow)
        wait(1.5)
        app.swipeUp(velocity: .slow)
        wait(1.5)
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        wait(2)
    }

    // MARK: - Помощники

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func wait(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @discardableResult
    private func tap(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        return true
    }

    /// Разрешения на микрофон и распознавание речи (системные окна).
    private func allowSystemAlerts() {
        for _ in 0..<2 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2.5) else { return }
            for title in ["Allow", "OK", "Разрешить", "ОК"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                break
            }
            if alert.exists, alert.buttons.count > 1 {
                alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
            }
            wait(1)
        }
    }
}
