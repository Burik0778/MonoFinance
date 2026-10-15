# Задача: ассистент MONO с нейросетью (Groq / Cerebras / OpenRouter / Gemini)

Приложение — SwiftUI, iOS 18. Логика — в пакете `Packages/MonoKit` (файлы подхватываются SwiftPM сами),
новые файлы приложения нужно добавлять в `MonoFinance.xcodeproj/project.pbxproj` вручную (по образцу соседних).
Swift локально недоступен: компилятор и тесты — только GitHub Actions (`.github/workflows/ios.yml`,
запускается на push в `main` и `redesign`). Дизайн — чёрно-белая система `MonoFinance/DesignSystem`,
тексты интерфейса — по-русски, комментарии в коде — по-русски.

## Правила работы
- Работать в ветке `redesign`. **Коммит и push после каждого законченного шага** (не копить работу).
- В `main` — только после зелёной проверки всех трёх jobs (MonoKit tests, Build unsigned IPA, Simulator screenshots).
- **Никаких API-ключей** в коде, тестах, коммитах, README: репозиторий и .ipa публичные. Ключи вводит пользователь на телефоне.

## Что уже есть
- `MonoFinance/Core/Services.swift` — `AssistantRemoteClient` (старый формат: свой endpoint + Bearer).
- `MonoFinance/Core/SettingsStore.swift` — `llmEnabled`, `llmEndpoint`, `llmConsent`.
- `MonoFinance/Security/KeychainStore.swift` — ключ `llmToken`.
- `MonoFinance/Features/AI/AssistantView.swift` — локальный (офлайн) ассистент на `Packages/MonoKit/Sources/MonoIntelligence`.
- `MonoFinance/Features/Settings/SettingsScreens.swift` (~строка 296) — текущие настройки LLM.

## Что сделать
1. **Сервисы (готовые и свои).** Модель `LLMProvider` (id, name, baseURL, model, isEnabled) в UserDefaults, ключ — только
   в Keychain (отдельно на каждый сервис). Готовые, все через OpenAI-совместимый `POST {baseURL}/chat/completions`:
   - Groq — `https://api.groq.com/openai/v1`, модель `llama-3.3-70b-versatile`
   - Cerebras — `https://api.cerebras.ai/v1`, модель `llama-3.3-70b`
   - OpenRouter — `https://openrouter.ai/api/v1`, модель `meta-llama/llama-3.3-70b-instruct:free` (+ заголовки `HTTP-Referer`, `X-Title: MONO Finance`)
   - Gemini — `https://generativelanguage.googleapis.com/v1beta/openai`, модель `gemini-2.5-flash`
   Экран «Нейросеть» в настройках: список, выбор активного, редактирование (название, адрес, модель, ключ — SecureField),
   «Проверить» (короткий тестовый запрос), «Добавить сервис», удаление своих, сброс готовых. Только https.
   Если активный не ответил (сеть, 429, 5xx) — пробовать следующий с ключом и показать, кто ответил.
2. **Приватность.** Наружу уходит только сводка, посчитанная на телефоне (MonoIntelligence/MonoAnalytics): итоги по месяцам,
   топ категорий и продавцов, средние, регулярные траты/подписки, бюджеты, сравнение периодов. `PrivacySanitizer` в MonoKit
   вычищает из любого текста номера карт (в т.ч. «414084******7058», «•• 1234»), последние 4 цифры, номера счетов
   (цифры ≥ 8 подряд), RRN/TID/MID/номера документов, телефоны, e-mail, паспорт, имена людей из переводов
   («перевод человеку»), заметки и теги. Названия продавцов и вопрос пользователя — тоже через него. Unit-тесты обязательны.
3. **Чат** в ассистенте: несколько сообщений, системный промпт по-русски (личный финансовый помощник, кратко, только по
   данным, конкретные советы по экономии). Подсказки: «На что я трачу больше всего?», «Где можно сэкономить?»,
   «Сравни этот месяц с прошлым», «Какие подписки и регулярные траты?». Экран «Что будет отправлено» (точный текст сводки),
   явное согласие (`llmConsent`). Ошибки по-русски: неверный ключ, лимит запросов, нет сети. Без сети / без согласия —
   прежние локальные ответы. Таймаут ~30 с, ключи не логировать.
4. README: коротко, где вводить ключи и что именно отправляется.
