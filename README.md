# Autonotes

Autonotes создаёт конспекты из фотографий лекционных материалов: сохраняет изображения, распознаёт текст и формирует краткое содержание через Ollama. Это собственный проект команды БПИ2304; командная копия технически является форком IWKMS99/Autonotes.

**ЛР № 1:** материалы в ветке `lab-1`, лицензию и план обсудим с преподавателем. [Чек-лист сдачи](docs/lab-1-submission.md) · [Результаты проверок](docs/lab-1-verification.md). Требования FR будут оформлены в ЛР № 2.

## Документация

- [Паспорт, команда, структура, карта функций, практики и план](docs/00-project.md).
- [Протокол проверок](docs/lab-1-verification.md) и [порядок сдачи](docs/lab-1-submission.md).
- [ML-сервис](ml/docs/ML_SERVICE.md), [существующие LikeC4-модели](architecture/README.md), [контракт логирования](docs/logging-contract.md).
- [История изменений](CHANGELOG.md).

## Устройство приложения

React SPA → Nginx → Spring Boot API. PostgreSQL хранит пользователей, конспекты и Outbox; MinIO — фотографии. RabbitMQ передаёт задания Python worker, который вызывает отдельно развёрнутую Ollama и возвращает результат. Frontend опрашивает состояние конспекта. Дополнительно предусмотрены метрики, трассировки, логи и кластерный режим.

Код и тесты находятся в компонентах `backend`, `frontend` и `ml`. Корневые `src/` и `tests/` содержат навигацию и общий тестовый материал. Размещение согласуем с преподавателем.

## Запуск

### Подготовка среды

Нужны Git, Windows PowerShell 5.1 или PowerShell 7, работающий Docker Desktop с Linux-контейнерами и Compose v2+. Для основного сценария нужны Ollama и загруженная vision-модель. Подготовленный MinIO-образ рассчитан на amd64. Java, Node и Python на хост для Docker-запуска не требуются.

Среду готовят один раз. Проверено на Windows, 32 ГиБ RAM и RTX 5070 с 12 ГиБ VRAM; минимальные требования отдельно не определяли. Для образов нужно несколько гигабайт, для модели — около 3,2 ГБ. CPU-режим не проверяли.

Вариант для NVIDIA GPU: отдельный официальный контейнер Ollama. На Windows требуется работающий GPU в Docker Desktop/WSL2. Подготовка:

```powershell
docker run -d --gpus all --name autonotes-lab1-ollama -v autonotes-lab1-ollama:/root/.ollama -p 127.0.0.1:11434:11434 ollama/ollama:0.40.17
docker exec autonotes-lab1-ollama ollama pull qwen2.5vl:3b
```

При повторном использовании уже созданного контейнера: `docker start autonotes-lab1-ollama`. Не выполнять повторно `docker run` с тем же именем. Если используется установленная Ollama, достаточно запущенного сервера и `ollama pull qwen2.5vl:3b`; его доступность из Docker проверит сценарий запуска.

Для удалённой Ollama используйте собственный доступный адрес, например через Tailscale. Хост модели должен быть включён; доступ с вашей машины и из ML-контейнера обязателен. Подробности — в документации ML. Модель и fallback должны быть загружены; по умолчанию оба поля равны `qwen2.5vl:3b`, поэтому скрытая загрузка 7b не требуется.

### Четыре команды из чистого клона

После подготовки среды:

```powershell
git clone https://github.com/dmice9/Autonotes.git
cd Autonotes
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start.ps1 -OllamaBaseUrl http://host.docker.internal:11434 -OllamaModel qwen2.5vl:3b
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke.ps1
```

До слияния ЛР № 1 первая команда для проверки её ветки: `git clone --branch lab-1 https://github.com/dmice9/Autonotes.git`. После слияния используется обычная команда выше. В PowerShell 7 вместо `powershell` можно вызвать `pwsh`.

`ExecutionPolicy Bypass` действует только на этот процесс. Скрипт создаёт `.env`, если его нет, меняет только переданные параметры, проверяет Docker и доступ к модели из ML-контейнера, собирает приложение и ждёт готовности сервисов. Данные при повторном запуске сохраняются.

Удалённый сервер задаётся параметром `-OllamaBaseUrl http://АДРЕС:11434`. Для другой изолированной базы можно передать `-ProjectName autonotes-clean`; одновременно два полных стека по умолчанию используют одинаковые порты, поэтому первый нужно остановить без удаления данных.

### Проверка вручную в три шага

1. Открыть `http://localhost:3000`, зарегистрироваться и войти.
2. Создать конспект с названием и файлом `tests/fixtures/lecture.png`.
3. Дождаться состояния «Готов», проверить текст про database transactions и осмысленное краткое содержание; повторно открыть конспект из списка.

`smoke.ps1` проверяет регистрацию, вход, профиль, загрузку, реальный OCR и суммаризацию, список, удаление и ограничения доступа. Ожидаются строки PASS и `passed: true` в `artifacts/lab-1/smoke.json`. Проверка `/health` сама по себе не подтверждает работу OCR.

Таймаут обработки — 600 секунд, меняется через `-TimeoutSec`. Скрипт создаёт технические аккаунты и удаляет только свой тестовый конспект. Пароли и токены не записываются в отчёт; отчёты и `.env` исключены из git.

### Адреса

| Сервис | Адрес |
|---|---|
| Приложение | http://localhost:3000 |
| Backend | http://localhost:8090 |
| Swagger | http://localhost:8090/swagger-ui.html |
| ML health | http://localhost:8000/health |
| MinIO console | http://localhost:9001 |
| RabbitMQ console | http://localhost:15672 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3001 |
| Jaeger | http://localhost:16686 |
| Kibana | http://localhost:5601 |

Пароли шаблона предназначены для локальной учебной среды. Нельзя публиковать реальный `.env` и JWT. Docker frontend использует `/api/v1`; адрес в `.env.example` предназначен также для локальной разработки React через порт 8090.

### Диагностика и остановка

```powershell
docker compose --project-name autonotes ps
docker compose --project-name autonotes logs --tail 100 backend-1 ml
docker compose --project-name autonotes down
```

`down` без `--volumes` сохраняет данные. Не удаляйте volumes работающих проектов. Если Engine недоступен, запустите Docker Desktop. Если модель не найдена — выполните её pull; если недоступна сеть — проверьте URL и настройки хоста. При ошибке сборки сохраните первую причину, а не только итоговый exit code. Нерешённые проблемы оформляются в issues.

### Версии

| Инструмент | Конфигурация |
|---|---|
| Java / Spring Boot / Gradle | Temurin 24.0.2+12 / 3.5.7 / Wrapper 8.14.3 |
| Node.js / npm / React | 22.23.5 / 10.9.9 / 19; точное дерево npm в package-lock.json |
| Python | 3.12.16 в контейнере; точные пакеты в ml/requirements.txt |
| Ollama / модель | 0.40.17 / qwen2.5vl:3b |
| Docker / Compose машины проверки | 29.9.3 / v5.7.0 |

Образы закреплены по digest в `docs/runtime-images.lock.json`. MinIO собирается из официального бинарника с проверкой SHA-256 — [подробнее](infrastructure/minio/README.md).

### Протокол повторного запуска

23.11.2026 проверили запуск на Windows 11 Pro. Полный E2E прошёл дважды: в рабочей среде (18,19 с обработки) и в чистом клоне `7c222f6` с новыми volumes (9,12 с). Модель и образы использовались из кэша. Это повтор на том же ПК. [Протокол и результаты](docs/lab-1-verification.md).

У модели есть ошибки терминологии — [#7](https://github.com/dmice9/Autonotes/issues/7). Smoke проверяет работу обработки и права доступа, но не точность всех формулировок.

## Инженерные проверки

В подготовленной среде соответствующего компонента:

- Backend: предварительно собрать MinIO по `infrastructure/minio/README.md`; затем `cd backend` и `./gradlew build` (Windows: `gradlew.bat build`); интеграционные тесты требуют Docker.
- Frontend: `cd frontend`, `npm ci`, `npm test -- --watchAll=false`, `npm run build`.
- ML: `python -m pip install -r ml/requirements.txt`, `python -m pytest ml/tests -q`.

GitHub Actions запускает существующие проверки. Unit-тесты ML используют mock модели; они не заменяют E2E с реальной Ollama. Фактические результаты CI должны проверяться в конкретном PR.

## Git и синхронизация исходного репозитория

Основная ветка — `main`. Каждая лабораторная выполняется в `lab-N`, включается через PR и после завершения получает тег `lab-N`. Каждый участник использует собственную авторизацию и автора коммитов. Итоговые согласования преподавателя остаются в product.

`origin` — `https://github.com/dmice9/Autonotes.git`; `upstream` — `https://github.com/IWKMS99/Autonotes.git`. Для получения изменений исходного проекта:

```powershell
git remote add upstream https://github.com/IWKMS99/Autonotes.git
git fetch upstream
git switch -c sync-upstream origin/main
git merge upstream/master
```

Remote добавляется один раз. После слияния разрешить конфликты, выполнить проверки и открыть PR в main. Исходная ветка upstream называется master.

## Дополнительные возможности

Исходный Compose содержит кластерный профиль из трёх backend и конфигурации Nginx/Prometheus; это дополнительный режим вне основного сценария ЛР № 1. LikeC4: в `architecture/` выполнить `npm ci` и `npm start`. Эти действия не входят в четыре команды запуска приложения.

## Лицензия

Лицензию пока не выбрали. Вопрос записан в [#2](https://github.com/dmice9/Autonotes/issues/2), обсудим его на занятии.
