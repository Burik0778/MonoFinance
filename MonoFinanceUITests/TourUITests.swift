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
            field.typeText("Сегодня купил кроссовки в Адидасе за 845 тысяч и потратил 40 тысяч на такси")
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
        let voiceSaved = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'адидас' OR label CONTAINS[c] 'adidas'")).firstMatch
        XCTAssertTrue(voiceSaved.waitForExistence(timeout: 3), "Операция из голосовой фразы не появилась в ленте")

        // Главная: лента операций — открываем первую операцию и возвращаемся.
        let firstRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'сум'")).element(boundBy: 1)
        if tap(firstRow) {
            wait(2)
            XCTAssertTrue(app.navigationBars["Операция"].waitForExistence(timeout: 3), "Карточка операции не открылась")
            back()
        }

        // Поиск и вся история.
        XCTAssertTrue(tap(button("Поиск")), "Нет кнопки поиска на главной")
        wait(2)
        XCTAssertTrue(app.navigationBars["Операции"].waitForExistence(timeout: 3), "История операций не открылась")
        app.swipeUp(velocity: .slow)
        wait(1.2)
        back()

        // Статистика: главное и подробный разбор.
        XCTAssertTrue(tap(button("Статистика")), "Нет кнопки статистики на главной")
        wait(2)
        XCTAssertTrue(app.staticTexts["Статистика"].waitForExistence(timeout: 3), "Статистика не открылась")
        app.swipeUp(velocity: .slow)
        wait(1.5)
        tap(button("Подробный разбор"))
        wait(1.5)
        for _ in 0..<2 {
            app.swipeUp(velocity: .slow)
            wait(1.2)
        }

        // Планы — из статистики.
        XCTAssertTrue(tap(button("Бюджеты и цели")), "Нет перехода к планам")
        wait(2)
        XCTAssertTrue(app.staticTexts["Планы"].waitForExistence(timeout: 3), "Планы не открылись")
        app.swipeUp(velocity: .slow)
        wait(1.5)
        back()
        back()

        // Выбор счёта на главной.
        XCTAssertTrue(tap(button("Выбрать счёт")), "Нет выбора счёта")
        wait(1.5)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kapital'")).firstMatch)
        wait(2)
        tap(button("Выбрать счёт"))
        wait(1.2)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Все счета'")).firstMatch)
        wait(1.5)

        // Новый расход с цифровой клавиатуры.
        XCTAssertTrue(tap(button("Новая операция")), "Нет строки «Новая операция»")
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
        let newExpense = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Такси'")).firstMatch
        XCTAssertTrue(newExpense.waitForExistence(timeout: 3), "Новая операция не появилась в ленте")

        // Настройки.
        XCTAssertTrue(tap(button("Настройки")), "Нет кнопки настроек")
        wait(2)
        app.swipeUp(velocity: .slow)
        wait(1.5)
        app.swipeUp(velocity: .slow)
        wait(1.5)
        back()
        wait(2)
    }

    private func back() {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        wait(1.2)
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
