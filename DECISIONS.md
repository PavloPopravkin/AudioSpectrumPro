# Decision Log - AudioSpectrumPro

> Что это: журнал архитектурных решений - ПОЧЕМУ выбрали так и ЧТО отвергли.
> Агент читает это первым перед нетривиальной правкой, чтобы не переспоривать закрытые вопросы.
> Как вести: новые записи сверху. Запись без строки "Отвергли:" - это факт, не решение (место в memory).
> Схема: ## YYYY-MM-DD · Название / - Решение / - Отвергли: альт - почему нет / - Почему / - Триггер / - Owner / - Связь: [[memory]]

---

## 2026-07-03 · In-app аналитика: переиспользуем свой Umami, анонимно, opt-out, отдельным релизом 1.2
- **Решение:** аналитика в приложении через self-hosted Umami (тот же инстанс, что и сайт; app-события шлём на synthetic hostname `audiospectrum.app`, чтобы отделить от веба). `Analytics.swift` - POST на `/api/send`, fire-and-forget, off-main, без device-id/IDFA/звука (Umami сам считает анонимный daily-rotating хэш из IP+UA). Есть opt-out тумблер в settings-шите (дефолт вкл/анонимно). Выкатываем **отдельно версией 1.2 после аппрува 1.1**, НЕ фолдим в текущее ревью.
- **Отвергли:** (а) TelemetryDeck/Aptabase - нативнее для iOS, но TelemetryDeck сторонний клауд, Aptabase = поднимать новый сервис; Umami уже развёрнут и в нашем контроле, ноль новой инфры, один дашборд с сайтом; (б) Firebase/Amplitude - privacy-инвазивно, противоречит позиционированию "collects nothing"; (в) вкрутить в 1.1 - задержало бы уже поданную версию на новый цикл ревью.
- **Готча (проверено):** Umami режет bot-like User-Agent (отдаёт `{"beep":"boop"}` вместо токена и НЕ пишет событие). App обязан слать iOS-образный UA (`AudioSpectrumPro/x (iPhone; CPU iPhone OS y like Mac OS X) Mobile`) - тогда возвращается `cache`-токен.
- **Триггер:** Pavel попросил аналитику в приложении (сначала я по ошибке поставил только на лендинг).
- **Owner:** Claude / Pavel (выбор Umami + тайминг 1.2)
- **Связь:** [[appstore-publishing]], [[landing-site-deploy]], `DEBT.md`

## 2026-07-02 · Тюнер: YIN вместо FFT-пика
- **Решение:** питч-детекция тюнера переведена на YIN (time-domain, CMND + параболическая интерполяция), новый `PitchDetector.swift`; FFT-метод `detectPitch` в `FFTProcessor` оставлен, но из пайплайна убран.
- **Отвергли:** оставить FFT-пик с квадратичной интерполяцией - на низких струнах (E2 82 Hz) разрешение бина ~10.7 Hz слишком грубое, и гармоники сильнее фундаментала дают октавные ошибки.
- **Почему:** все серьёзные тюнеры работают на YIN/автокорреляции; vDSP-реализация укладывается в ~2.5M MAC на кадр - незаметно на фоновом потоке.
- **Триггер:** пакет улучшений v1.1.
- **Owner:** Claude

## 2026-07-02 · Loudness: честный BS.1770 (LUFS M/S/I + dBTP) вместо RMS
- **Решение:** новый `LoudnessProcessor.swift` - K-weighting (коэффициенты из аналоговых прототипов BS.1770 под реальный sample rate, как в libebur128), momentary 400ms / short-term 3s / integrated с двухступенчатым гейтингом (-70 LUFS абсолютный, -10 LU относительный), true peak через 4× polyphase windowed-sinc оверсемплинг с session-max hold.
- **Отвергли:** (а) оставить RMS dBFS с подписью "Loudness" - не соответствует названию "Pro", RMS ≠ воспринимаемая громкость; (б) старый "true peak" = sample peak без оверсемплинга + странный decay `*0.999` который полз ВВЕРХ к нулю.
- **Почему:** LUFS - стандарт стриминга/мастеринга и главный аргумент "Pro" в сторе; блочные границы гейтинга привязаны к буферам захвата (джиттер ≤85ms) - осознанное упрощение, на integrated не влияет.
- **Триггер:** пакет улучшений v1.1.
- **Owner:** Claude

## 2026-06-18 · Реджект 2.1 - отвечаем демо-видео + пояснением, не пересобираем
- **Решение:** на реджект Guideline 2.1 (ревьюер ошибочно решил, что нужно «designated hardware pairing») отвечаем связкой: демо-видео работы на живом iPhone (только встроенный микрофон) + явное пояснение в Resolution Center, что внешнего железа и pairing-процесса нет. Переподаём **тот же билд** (это Information Needed, не дефект бинарника).
- **Отвергли:** (а) ответить только текстом «железа нет» без видео - риск, что ревьюер всё равно захочет увидеть работу приложения (угол App Completeness) → +48ч на ещё один круг; (б) пересобирать/бампать билд - не нужно, код корректен, проблема чисто в коммуникации.
- **Почему:** «не спорить, а перевыполнить» - дать ровно то, что просят (видео на physical device), и заодно снять недоразумение про железо одним заходом. Подтверждено по коду: `.entitlements` пуст, нет ExternalAccessory/MFi/CB-pairing, только встроенный мик+динамик.
- **Триггер:** реджект Apple 2.1 от 2026-06-18, Submission ID `344bd2e7-3c32-42d6-901e-d9203f6c7443`.
- **Owner:** Claude / Pavel (видео снимает папа)
- **Связь:** [[appstore-publishing]], `DEBT.md`

## 2026-06-16 · Сабмит на ревью через modern reviewSubmissions API
- **Решение:** финальный сабмит билда на ревью делать через современную связку `reviewSubmissions` + `reviewSubmissionItems` + PATCH `submitted:true`.
- **Отвергли:** legacy `appStoreVersionSubmissions` POST - Apple его уже запретил (forbidden now), запрос не проходит.
- **Почему:** сабмит молча блокировался; пока не заполнили весь чеклист (age rating, privacy URL ×3, copyright, contentRightsDeclaration на ресурсе app, категории, reviewDetail, pricing) и не перешли на новый API - кнопка submit не срабатывала.
- **Триггер:** первая публикация, обнаружен silently blocked submit.
- **Owner:** Claude
- **Связь:** [[appstore-publishing]], `AppStore/metadata.md`

## 2026-06-16 · releaseType = MANUAL (Pavel жмёт Release)
- **⚠️ SUPERSEDED 2026-06-21:** на деле переподанная версия вышла с `releaseType=AFTER_APPROVAL` (видимо переключилось в веб-UI при resubmit в Resolution Center) и **зарелизилась автоматически** после аппрува - ручной Release не понадобился. v1.0 уже `READY_FOR_SALE`. Это решение в силе только для будущих версий, если их явно вернуть на MANUAL.
- **Решение:** релиз после аппрува - ручной (`releaseType=MANUAL`), Pavel сам кликает Release.
- **Отвергли:** автоматический релиз сразу после одобрения - не хотим, чтобы версия ушла в стор без явного решения Pavel'я.
- **Почему:** контроль момента публикации остаётся за человеком.
- **Триггер:** заполнение submission-чеклиста через ASC API.
- **Owner:** Pavel
- **Связь:** [[appstore-publishing]]

## 2026-06-16 · Имя приложения "Audio Spectrum Pro: Analyzer"
- **Решение:** имя в App Store - "Audio Spectrum Pro: Analyzer".
- **Отвергли:** простое "Audio Spectrum Pro" - имя уже занято в App Store.
- **Почему:** глобально уникальное имя обязательно; добавили ": Analyzer" чтобы пройти проверку уникальности.
- **Триггер:** создание app record в ASC.
- **Owner:** Pavel
- **Связь:** [[appstore-publishing]]

## 2026-06-16 · Публикация под VADMAX team, не croscor
- **Решение:** приложение публикуется под командой VADMAX SP Z O O (Team ID `82532N5BVJ`); `DEVELOPMENT_TEAM` в `project.pbxproj` исправлен на этот ID.
- **Отвергли:** трактовать `croscor.*` bundle-префикс как указание на команду croscor - это просто reverse-DNS, к команде отношения не имеет; старый `DEVELOPMENT_TEAM = CYS83XVF42` ни на что не матчился.
- **Почему:** неверный team ID давал "No Account for Team (Personal Team)" на архиве; seller в сторе = VADMAX SP Z O O.
- **Триггер:** archive failure при первой сборке.
- **Owner:** Claude
- **Связь:** [[appstore-publishing]]

## 2026-06-16 · Сборка и заливка через CLI, без Xcode GUI
- **Решение:** весь пайплайн (`xcodebuild archive` → `-exportArchive` → `altool --validate-app` → `altool --upload-app`) гоним из CLI с ASC API-ключом и `-allowProvisioningUpdates`, префикс `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Отвергли:** Xcode GUI (Organizer/Archive/Distribute вручную) - не нужен, весь процесс воспроизводим из терминала.
- **Почему:** ключ сам создал Apple Distribution cert + App Store profile (у аккаунта их не было); CLT - активный dev dir, поэтому каждую команду надо префиксить на Xcode toolchain.
- **Триггер:** первая публикация AudioSpectrumPro.
- **Owner:** Claude
- **Связь:** [[appstore-publishing]]

---

## Standing / foundational (действует постоянно)

## ∞ · nginx vhost для *.croscor.com - specific-IP listen
- **Решение:** vhost `audiospectrum.croscor.com` (и любой croscor-сабдомен на Server 1) слушает на конкретном IP: `listen 194.31.52.56:80/:443` + IPv6 `[2a02:4780:c:56be::1]`, по образцу imba/yurtec.croscor.com.
- **Отвергли:** generic `listen 80;` - попадает в неправильную listen-группу, ломает Host-роутинг и отдаёт ACME http-01 на перехват catch-all'у.
- **Почему:** иначе сайт не резолвится по своему домену и Let's Encrypt не выпускает cert.
- **Owner:** Claude
- **Связь:** [[landing-site-deploy]], `AppStore/deploy/nginx-audiospectrum.croscor.com.conf`
