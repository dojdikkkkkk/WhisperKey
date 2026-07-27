# WhisperKey

**Локальная диктовка для macOS по правому ⌘ с опциональным облачным STT.** Говоришь в любом приложении — текст появляется у курсора через ~2 секунды. Можно запускать Whisper на GPU Apple Silicon через [MLX](https://github.com/ml-explore/mlx) или подключить свой ключ OpenAI-совместимого API.

[English version →](README.md)

## Возможности

- **Одна клавиша, два режима** — *зажал* правый ⌘ — push-to-talk, *тапнул* — длинная запись до следующего тапа. Обычные шорткаты с правым ⌘ не ломаются.
- **Свечение моноброви** — анимация в стиле Apple Intelligence вокруг выреза MacBook: тёплые цвета — запись, холодные — распознавание, зелёная вспышка — текст вставлен. На внешнем мониторе рисуется виртуальная монобровь.
- **Локальный или облачный STT** — whisper-large-v3-turbo на GPU, готовый пресет Groq или другой OpenAI-совместимый endpoint.
- **Словарь терминов** — «спид точка центер» → `spid.center`: список терминов подсказывает декодеру Whisper, regex-правила добивают остальное.
- **Самообучение** — LLM просматривает свежие диктовки и сам дописывает словарь. Работает с локальной LLM (Ollama), CLI-агентами (Claude Code, Codex) или вручную через любого агента.
- **Мастер настройки** — выбор Local MLX или Cloud API, модели и способа обучения в нативном окне.
- **Приватность** — Local MLX оставляет аудио на Mac. В Cloud API ключ хранится в macOS Keychain, а аудио уходит только на указанный endpoint.

## Требования

Apple Silicon (M1+), macOS 14+, Xcode Command Line Tools, Python 3.10+.

## Установка

Одной строкой:

```bash
curl -fsSL https://raw.githubusercontent.com/dojdikkkkkk/WhisperKey/main/install.sh | bash
```

При первом запуске откроется мастер настройки. **Local MLX** скачает модель при первом использовании; **Cloud API** работает без скачивания весов модели.

### Права (важно!)

System Settings → Privacy & Security: **Microphone** и **Accessibility** (Универсальный доступ).

Грабли, собранные лбом:

- После выдачи Accessibility **перезапусти приложение** — на живой процесс право не действует.
- Хоткей работает и *без* Accessibility (мониторинг модификаторов не требует прав), поэтому «запись идёт, а текст не появляется» = почти всегда отсутствующее/протухшее право Accessibility.
- Сборка без сертификата (ad-hoc) сбрасывает право **при каждой пересборке**. `build.sh` сам подхватывает Apple Development сертификат — бесплатно создаётся в Xcode.

## Настройка

Конфиг: `~/.whisperkey/config.json` + окно **Settings…** в меню-баре. Основные ключи STT: `transcriptionBackend` (`local`/`openai`), `model` для Local MLX, а также `cloudProvider`, `cloudEndpoint` и `cloudModel` для Cloud API. API-ключ хранится отдельно в macOS Keychain и в JSON не записывается. Остальные ключи: `learnBackend` (`ollama`/`claude`/`codex`/`agent-manual`/`off`), `ollamaModel`, `holdThreshold`, `learnEvery`, `logTranscripts`.

### Облачное распознавание

В **Settings… → Speech-to-text** выбери **Cloud API**. Пресет **Groq** подставит endpoint `https://api.groq.com/openai/v1/audio/transcriptions` и модель `whisper-large-v3-turbo` (в прямом API Groq — без префикса `groq/`). В режиме **Custom** можно указать полный OpenAI-совместимый endpoint и имя модели провайдера или шлюза.

После ввода ключа нажми **Save & Use Cloud STT**. Удалённые endpoint должны использовать HTTPS; HTTP разрешён только для localhost. В облачном режиме аудио и термины из glossary prompt отправляются выбранному провайдеру. При ошибке появится уведомление macOS; автоматического перехода на локальную модель нет.

## Словарь и самообучение

`server/glossary.json`: `terms` (подсказка активному STT-бэкенду) + `rules` (regex-замены). Файл перечитывается на лету. Засев из своих текстов: `server/seed_glossary.py --help`. С включённым `learnBackend` словарь пополняется сам каждые 20 диктовок; бэкенд `agent-manual` пишет задание в `server/learn_request.md` для любого твоего агента (см. [AGENTS.md](AGENTS.md)).

## Диагностика

Симптомы и лечение — в таблице Troubleshooting английского README. Главное: «запись есть, текста нет» → перевыдай Accessibility и перезапусти приложение. Для Cloud API проверь уведомление macOS, endpoint, имя модели, ключ в Keychain, лимиты аккаунта и `server/server.log`.

## Лицензия

[MIT](LICENSE)
