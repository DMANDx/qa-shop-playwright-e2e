# qa-shop-playwright-e2e

E2E-тесты на **C# / NUnit / Playwright** для учебного интернет-магазина «Лавка» (`qa-shop`).

Публичный репозиторий: <https://github.com/DMANDx/qa-shop-playwright-e2e>  
Публичный адрес магазина: **<https://qa-shop-dmand-2026.loca.lt>**

Магазин открывается из интернета без VPN. Приложение запущено на ПК как Node.js-процесс
(`node server.js`, порт 3000 — тот же образ, что описан в `Dockerfile` архива), а публичный адрес
обеспечивается HTTP-туннелем `localtunnel` с того же ПК.

> ⚠️ localtunnel при первом заходе с нового публичного IP показывает страницу-предупреждение.
> Введите на ней IP, который там же показан, и нажмите **Continue**. Это делается один раз в 7 дней
> для каждого IP. Тесты проходят это предупреждение автоматически с помощью заголовка
> `bypass-tunnel-reminder: 1`.

## Что покрыто тестами

| Сценарий | Файл | Тесты |
|---|---|---|
| Каталог: вывод 16 товаров, фильтр по категории | `CatalogTests.cs` | `Catalog_shows_products_and_filters_by_category` |
| Поиск по названию и описанию, пустой результат | `CatalogTests.cs` | `Search_finds_by_name_and_description_and_handles_empty_result` |
| Сортировка по цене (asc/desc) | `CatalogTests.cs` | `Sort_changes_order_by_price` |
| Карточка товара и добавление нужного количества | `CatalogTests.cs` | `Product_page_adds_selected_quantity_to_cart` |
| Корзина: изменение количества, удаление, очистка | `CartTests.cs` | `Cart_updates_quantity_removes_and_clears_items` |
| Ограничение по остатку в корзине | `CartTests.cs` | `Cart_rejects_quantity_above_stock_with_error_toast` |
| Промокоды `SALE10`, `WELCOME500`, сброс и ошибки | `PromoTests.cs` | 4 теста |
| Оформление: курьер, самовывоз, бесплатная доставка от 3000 ₽, валидация, промокод в заказе | `CheckoutTests.cs` | 5 тестов |
| Регистрация, логин/логаут, история заказов, валидации | `AuthTests.cs` | 3 теста |
| Воспроизведения найденных багов | `KnownBugTests.cs` | 4 теста (пока отключены через `[Ignore]`) |

Результат последнего прогона (и локально, и через публичный URL):

```text
Пройдено: 18, Пропущено: 4, Не пройдено: 0
```

4 пропущенных теста — это заготовки-репродукции багов. Снимите атрибут `[Ignore]`, чтобы
убедиться, что они падают на текущей версии приложения.

## Запуск тестов

Требования: .NET SDK 8.0+, доступ к магазину (`http://localhost:3000` или публичный URL).

```powershell
# 1. Восстановление и сборка
dotnet restore
dotnet build

# 2. Установка браузера Chromium для Playwright (один раз)
.\bin\Debug\net8.0\playwright.ps1 install chromium
# если ExecutionPolicy запрещает скрипт:
powershell -ExecutionPolicy Bypass -File .\bin\Debug\net8.0\playwright.ps1 install chromium

# 3. Прогон против локального магазина
$env:SHOP_BASE_URL = 'http://localhost:3000'
dotnet test

# 3b. Прогон против публичного магазина
$env:SHOP_BASE_URL = 'https://qa-shop-dmand-2026.loca.lt'
dotnet test
```

Для Windows есть вспомогательный скрипт, который делает restore/build/install/dotnet test:

```powershell
.\run-tests.ps1 -BaseUrl 'https://qa-shop-dmand-2026.loca.lt'
```

На Linux/macOS:

```bash
SHOP_BASE_URL=https://qa-shop-dmand-2026.loca.lt dotnet test
```

### Переменные окружения

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `SHOP_BASE_URL` | `http://localhost:3000` | Адрес тестируемого магазина |

Каждый тест получает свежий `BrowserContext` (изоляция cookie/cart) и перед стартом вызывает
`POST /api/test/reset`. Для этого сервер должен быть запущен с `ALLOW_TEST_RESET=1`. Если флаг
не задан, endpoint вернёт 404, и тесты продолжат работать на текущих данных — лучше всего
использовать отдельный тестовый инстанс магазина.

Тесты идут последовательно (`AssemblyInfo.cs` → `[assembly: NonParallelizable]`), потому что сброс
данных — глобальный для сервера.

## Мониторинг

Grafana доступна по постоянной ссылке: **<https://dmandx.github.io/qa-shop-playwright-e2e/grafana/>**  
Она всегда перенаправляет на актуальный HTTPS-туннель: страница читает `docs/tunnel.json` с
запросом без кэша, поэтому старый адрес из кэша браузера не помешает. При первом открытии
`tunnl.gg` покажет страницу **Before you continue** — нажмите **Continue to site**. Анонимный доступ
с ролью Viewer включён, дашборд открывается сразу. Для изменений можно войти как `admin` / `admin`.

Туннель поддерживается скриптом `monitoring/start-grafana-tunnel.ps1`: если пересылка рвётся,
скрипт поднимает новый URL, обновляет `GF_SERVER_ROOT_URL`, `tunnel.json` и публикует изменение
в GitHub Pages.

Дашборд **«QA Shop — обзор»** показывает:

- RPS по маршрутам, долю ошибок 4xx/5xx, latency p95/p99;
- заказы, выручку, добавления в корзину, регистрации и неудачные логины;
- активные сессии, товары без остатка, заказы по способу доставки;
- Node.js runtime: event loop lag, heap/RSS и CPU процесса.

Метрики снимаются Prometheus напрямую с `http://host.docker.internal:3000/metrics` каждые 5 секунд.
Конфигурация Prometheus, Grafana и дашборд лежат в каталоге `monitoring/`:

```powershell
cd monitoring
docker compose up -d
```

## Найденные баги

| ID | Severity | Что происходит | Воспроизведение | Ожидалось |
|---|---|---|---|---|
| BUG-01 | Medium | Кнопка «+» на карточке товара не ограничена `max` остатка. Можно выставить количество 6 при остатке 3; сервер вернёт 409, но невалидное значение останется в поле. | Открыть `#/product/11` (чайник, остаток 3), нажать «+» 5 раз. | Кнопка блокируется на 3, значение поля не превышает остаток. |
| BUG-02 | Low | Кнопка «+» в корзине активна на границе остатка. Клик по ней вызывает toast «В наличии только 3 шт.» вместо того, чтобы быть недоступной. | Добавить товар 11, открыть корзину, нажать «+» трижды. | Кнопка `disabled` при `qty >= stock`, ошибка не показывается. |
| BUG-03 | Medium | `POST /api/cart/items` с `qty: 0` (или нечисловым значением) молча добавляет **1 шт.** вместо ошибки. Причина: `Number(qty) \|\| 1` в `server.js`. | Отправить `{"productId":1,"qty":0}` с валидной cookie `sid`. | `400 {"error":"Некорректное количество"}`. |
| BUG-04 | Medium | При самовывозе поле «Адрес доставки» остаётся видимым, хотя получает атрибут `hidden`. Причина: `.form label { display: grid }` перебивает браузерный `[hidden] { display: none }`. | Оформить заказ, выбрать «Самовывоз». | Поле адреса скрыто. |

Все четыре бага оформлены тестами-репродукциями в `KnownBugTests.cs` и отключены через
`[Ignore("BUG-…")]`, чтобы основной прогон оставался зелёным. Снимите `Ignore` — тесты упадут
и покажут актуальное поведение.

### Замечания (не блокирующие)

- Обработчик `Выйти` в `public/app.js` и меняет `location.hash`, и вызывает `route()` вручную —
 _route() выполняется дважды_. В тестах это приводило к гонке с переходом на форму логина;
  обход — навигация с уникальным query-параметром в `ShopTestBase.OpenAsync`.
- Куки сессии выставляются без атрибута `Secure`. На HTTPS-туннеле это работает, но для
  продакшена атрибут стоит добавить.

## Структура

```text
.
├── QaShop.E2E.csproj
├── AssemblyInfo.cs          # последовательный прогон
├── ShopConfig.cs            # SHOP_BASE_URL, заголовки туннеля
├── ShopTestBase.cs          # сброс данных, helpers, web-first assertions Playwright
├── CatalogTests.cs
├── CartTests.cs
├── PromoTests.cs
├── CheckoutTests.cs
├── AuthTests.cs
├── KnownBugTests.cs
├── deploy/
├── monitoring/             # Prometheus + Grafana + дашборд
├── run-tests.ps1
└── README.md
```
