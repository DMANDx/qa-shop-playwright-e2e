using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Playwright;
using Microsoft.Playwright.NUnit;

namespace QaShop.E2E;

/// <summary>
/// Базовый класс: свежий BrowserContext на тест, сброс данных магазина через
/// POST /api/test/reset и набор вспомогательных методов для UI/API-проверок.
/// </summary>
[TestFixture]
public abstract class ShopTestBase : PageTest
{
    public override BrowserNewContextOptions ContextOptions() => new()
    {
        BaseURL = ShopConfig.BaseUrl,
        ExtraHTTPHeaders = ShopConfig.ExtraHeaders,
        ViewportSize = new ViewportSize { Width = 1440, Height = 900 },
    };

    [SetUp]
    public async Task ResetShopAsync()
    {
        // Если сервер запущен без ALLOW_TEST_RESET=1, endpoint вернёт 404 —
        // тесты продолжают работать, но считают, что данные уже «грязные».
        await Context.APIRequest.PostAsync(ShopConfig.Url("/api/test/reset"));
    }

    protected ILocator ProductCards =>
        Page.GetByTestId("product-list").Locator("[data-testid='product-card']");

    protected async Task OpenAsync(string route = "")
    {
        var hash = string.IsNullOrEmpty(route) || route == "/"
            ? "#/"
            : route.StartsWith('#') ? route : "#/" + route.TrimStart('/');

        // Уникальный query-параметр вызывает полноценную перезагрузку SPA и
        // устраняет гонку с обработчиками hashchange / явными вызовами route().
        await Page.GotoAsync(ShopConfig.Url($"/?t={Guid.NewGuid():N}{hash}"));
        await Expect(Page.Locator("header.header")).ToBeVisibleAsync();
    }

    protected async Task AddProductAsync(int productId)
    {
        await OpenAsync();
        await Expect(ProductCards.First).ToBeVisibleAsync();
        await Page.Locator($"[data-add='{productId}']").ClickAsync();
        await Expect(Page.Locator("#toast")).ToContainTextAsync("Товар добавлен");
    }

    protected async Task OpenCartAsync()
    {
        await Page.GetByTestId("cart-link").ClickAsync();
        await Expect(Page.Locator("main h1")).ToHaveTextAsync("Корзина");
    }

    protected async Task OpenCheckoutAsync()
    {
        await OpenCartAsync();
        await Page.Locator("#to-checkout").ClickAsync();
        await Expect(Page.Locator("#checkout")).ToBeVisibleAsync();
    }

    protected async Task<int> PlaceOrderAsync(
        string name,
        string phone,
        string address = "",
        bool courier = false)
    {
        await OpenCheckoutAsync();
        await Page.Locator("input[name='name']").FillAsync(name);
        await Page.Locator("input[name='phone']").FillAsync(phone);

        if (courier)
        {
            await Page.Locator("input[name='address']").FillAsync(address);
        }
        else
        {
            await Page.Locator("input[name='delivery'][value='pickup']").CheckAsync();
        }

        await Page.Locator("#submit-order").ClickAsync();
        await Expect(Page.GetByTestId("order-success")).ToBeVisibleAsync();

        var orderId = await Page.GetByTestId("order-id").TextContentAsync();
        return int.Parse(orderId!.Trim());
    }

    protected async Task<JsonElement> ApiGetAsync(string path)
    {
        var response = await Context.APIRequest.GetAsync(ShopConfig.Url(path));
        Assert.That(response.Ok, Is.True, $"GET {path} вернул {response.Status}");
        var json = await response.JsonAsync();
        return json!.Value;
    }

    /// <summary>Ожидает конкретной суммы в элементе с data-testid, игнорируя ₽ и пробелы.</summary>
    protected async Task AssertMoneyAsync(string testId, int expected)
    {
        // ₽ и разряды отделены узкими неразрывными пробелами — между цифрами допускаем любые нецифры.
        var digits = string.Join(@"\D*", expected.ToString().Select(c => c.ToString()));
        var amount = new Regex($@"(?<!\d){digits}(?!\d)");
        await Expect(Page.Locator($"[data-testid='{testId}']")).ToHaveTextAsync(amount);
    }

    protected static int ParseMoney(string? text) =>
        int.Parse(new string((text ?? string.Empty).Where(char.IsDigit).ToArray()));
}
