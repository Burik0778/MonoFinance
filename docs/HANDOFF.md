# Передача работы: MONO Finance (состояние на 16.10.2026)

Этот файл — всё, что нужно, чтобы продолжить в новом чате. Начните новый чат словами:
«Работаем в Burik0778/MonoFinance, ветка redesign. Прочитай docs/HANDOFF.md и продолжай».

## Правила работы (от пользователя)

- Репозиторий `Burik0778/MonoFinance`, ветка **`redesign`**. Коммит + push после каждого законченного шага.
- Проверка — только GitHub Actions (`.github/workflows/ios.yml`, на push в `main` и `redesign`), три jobs:
  MonoKit tests, Build unsigned IPA, Simulator screenshots.
- В `main` — только после зелёной проверки всех трёх jobs на `redesign` (fast-forward: `git push origin redesign:main`).
  Push в `main` сам публикует релиз `latest` с `MonoFinance.ipa`
  (https://github.com/Burik0778/MonoFinance/releases/download/latest/MonoFinance.ipa). Пользователь ставит его через Sideloadly.
- **Никаких API-ключей** в коде, тестах, коммитах, README — пользователь вводит их на телефоне.
- Писать пользователю по-русски, коротко. Тексты интерфейса и комментарии в коде — по-русски.
- В workflow `concurrency: cancel-in-progress` — новый push в ту же ветку отменяет идущую проверку.

## Окружение и приёмы

- Swift локально недоступен (и скачать нельзя): компилятор и тесты — только в CI.
- Новые файлы приложения нужно вручную добавлять в `MonoFinance.xcodeproj/project.pbxproj` (4 места: PBXBuildFile,
  PBXFileReference, группа, Sources). Файлы в `Packages/MonoKit` подхватываются сами.
- Приложение — Swift 5 mode, `SWIFT_STRICT_CONCURRENCY: minimal`; MonoKit — Swift 6 mode.
- Скриншоты CI публикуются в ветку `ci-shots-redesign` (для main — `ci-shots`), журнал сборки — `ci-logs-redesign`.
  Там же `crashes/` — журналы падений приложения в симуляторе, если были.
- Флаги запуска для снимков (только DEBUG, `MonoFinance/App/AppEnvironment.swift` → `DebugFlags`):
  `-monoTab overview|transactions|analytics|plans`, `-monoScope month|last30|last90|year`, `-monoDetails`,
  `-monoScroll top|center|bottom`, `-monoSheet assistant|import|…`, `-monoRoute …`, `-monoLight` и др. Список снимков — в ios.yml.
- Демо-данные — `MonoFinance/Core/DemoData.swift` (в т.ч. крошечные суммы в давних месяцах для проверки «Года»).
- Журнал сбоя с iPhone: Настройки → Конфиденциальность и безопасность → Аналитика и улучшения → Данные аналитики →
  `MonoFinance-…ips` → «Поделиться» → «Сохранить в Файлы» → прикрепить в чат.

## Что сделано в этой сессии

### Ассистент с нейросетью (задание `docs/AI_ASSISTANT_TASK.md`)
- `Packages/MonoKit/Sources/MonoIntelligence/PrivacySanitizer.swift` — вычищает карты (в т.ч. «414084******7058», «•• 1234»),
  последние 4 цифры, счета (8+ цифр), RRN/TID/MID/номера документов, телефоны, e-mail, паспорт, имена; переводы людям →
  «перевод человеку»; `stripped(_:)` убирает заметки, теги, чек. Тесты: `Tests/MonoIntelligenceTests/PrivacySanitizerTests.swift`.
- `FinancialSummary.swift` — `FinancialSummaryBuilder`: сводка для нейросети (итоги по месяцам, категории, сравнение,
  частые продавцы, средние, регулярные траты, бюджеты). Без операций, счетов, остатков, заметок.
- `LLMChat.swift` — `LLMProvider` (id, name, baseURL, model, isEnabled; presets Groq/Cerebras/OpenRouter/Gemini; только https;
  `fallbackOrder`, `mergingPresets`, `retiredModels` + `upgradingRetiredModels`, `modelsURL`), `LLMChatRequest`
  (max_tokens 2000), `LLMError` (вкл. `.service(status, detail)` с текстом сервиса), `LLMResponseParser`
  (text, isCompletion, errorMessage со скрытием длинных токенов, modelIDs, вырезание `<think>`), `LLMFallback`
  (перебор при сети/429/5xx), `LLMPrompt` (системный промпт по-русски, сборка сообщений через санитайзер, 4 подсказки).
- `ChatMarkdown.swift` — разбор ответа на блоки (заголовок, абзац, списки, таблица). Тесты: `ChatMarkdownTests.swift`.
- Приложение: `MonoFinance/Core/Services.swift` (`LLMKeychain` — ключ в Keychain `llmKey.<id>`; `LLMClient`: complete, ask с
  перебором, check, models), `Core/SettingsStore.swift` (`llmProviders`, `llmActiveProviderID`, `llmConsent`, `llmReady`),
  `Features/Settings/NeuralNetworkSettingsView.swift` (экран «Нейросеть», редактор сервиса, «Проверить», «Выбрать модель»,
  «Что будет отправлено» с согласием), `Features/AI/AssistantView.swift` (чат; без сети/согласия — локальные ответы;
  ответ нейросети — карточка `ChatReplyContent`). README — раздел «Нейросеть в ассистенте».
- Модели по умолчанию изменены (старые из задания отключены сервисами в 2026): Groq `openai/gpt-oss-120b`,
  Cerebras `gpt-oss-120b`, Gemini `gemini-flash-latest`, OpenRouter `meta-llama/llama-3.3-70b-instruct:free` (не проверено).
- Пользователь подтвердил: Cerebras отвечает в чате (подпись «Ответила нейросеть · Cerebras»).

### Статистика и валюты
- Крупные суммы с видимыми разрядами (`MoneySpacing.widened` в `DesignSystem/Components/MoneyText.swift`).
- Фильтр «Все траты / от 100 тыс. / …» (`ExpenseSizeFilter`, `LargeExpensesCard`; `AnalyticsEngine.filteringExpenses(atLeast:)`).
- Вылет на «Годе» (NaN в acos в Swift Charts): кольцо категорий нарисовано своими дугами (`DonutRing`), у мелких столбиков
  «Доходы и расходы» нет скругления (`TrendCard.radius`). Тест годового отчёта на «грязных» данных.
- Курсы: `CurrencyConverter` считает кросс-курсы через любую цепочку (курсы ЦБ к суму работают при основной USD/RUB),
  ручной курс «1 X = N Y», курсы ЦБ подтягиваются при любой основной валюте, рубль в выборе основной валюты.

## Ждёт проверки пользователем (последний релиз — коммит 3bb4e86)
1. «Статистика» → «Год» не вылетает на его данных.
2. «Проверить» у Cerebras, Groq, Gemini (и OpenRouter) — проходит или показывает точную ошибку; «Выбрать модель» работает.
3. Новый вид ответа нейросети в чате (на CI его не видно — там нет ключей).
4. Курсы и основная валюта USD/RUB — итог на главной без «0 $».

## Идеи, которые предлагались, но не сделаны
- Кнопка ассистента на главном экране (сейчас — только в «Статистике», значок ✦ справа вверху).
- Под ответом нейросети: модель и время ответа («Cerebras · gpt-oss-120b · 0,9 с»).
- «Наблюдения» в статистике всегда про текущий месяц, даже если выбран прошлый.
- У пользователя ~89 % трат «Без категории» — помочь разнести по категориям (правила по продавцам).
- Подсказка на главной: что такое «Всего на счетах» и как сверить с банком (кнопка «Баланс» в карточке счёта).
