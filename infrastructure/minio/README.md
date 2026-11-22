# Контейнер MinIO для воспроизводимого запуска

Исходный образ `minio/minio:RELEASE.2025-09-07T16-13-09Z-cpuv1` недоступен при проверке 23.11.2026 (pull access denied); Quay возвращает 401. Поэтому образ собирается локально из официального upstream-бинарника той же даты, с проверкой опубликованного SHA-256.

- [Бинарник и контрольные суммы](https://github.com/minio/minio/releases/tag/RELEASE.2025-09-07T16-13-09Z).
- [Соответствующий исходный код](https://github.com/minio/minio/tree/RELEASE.2025-09-07T16-13-09Z).
- [Лицензия MinIO AGPLv3](https://github.com/minio/minio/blob/RELEASE.2025-09-07T16-13-09Z/LICENSE).

MinIO является отдельным неизменённым сторонним компонентом; его лицензия не назначается исходникам Autonotes. Контейнер содержит официальный бинарник linux/amd64, поэтому этот путь запуска ограничен amd64. База зафиксирована digest в Dockerfile.

Локальное имя: `autonotes-minio:RELEASE.2025-09-07T16-13-09Z`. Compose собирает его автоматически. Перед backend-тестами:

```powershell
docker build -t autonotes-minio:RELEASE.2025-09-07T16-13-09Z infrastructure/minio
```

Testcontainers использует этот же образ как совместимую замену MinIO. В CI сборка выполняется до Gradle. Тег локальный; публикация образа от имени MinIO не выполняется.
