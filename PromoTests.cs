
namespace QaShop.E2E;

public class PromoTests : ShopTestBase
{
    [Test]
    public async Task Sale10_applies_ten_percent_discount()
    {
        await AddProductAsync(1); // 890 ₽
        await OpenCartAsync();

        // Регистр и пробелы должны нормализоваться сервером.
        await Page.GetByLabel("Промокод").FillAsync("  sale10 ");
        await Page.Locator("#promo button").ClickAsync();

        await Expect(Page.GetByTestId("discount")).ToBeVisibleAsync();
        await AssertMoneyAsync("discount", 89);
        await AssertMoneyAsync("subtotal", 890);
        await AssertMoneyAsync("total", 801);
        await Expect(Page.Locator("#promo input")).ToHaveValueAsync("SALE10");
    }

    [Test]
    public async Task Welcome500_requires_minimum_subtotal_and_then_discounts_500()
    {
        await AddProductAsync(1); // 890 ₽ — меньше минимума 2000 ₽
        await OpenCartAsync();

        await Page.GetByLabel("Промокод").FillAsync("WELCOME500");
        await Page.Locator("#promo button").ClickAsync();

        await Expect(Page.Locator("#toast")).ToContainTextAsync("Промокод действует при заказе от 2000 ₽");
        await Expect(Page.GetByTestId("discount")).ToHaveCountAsync(0);

        await AddProductAsync(2); // +2150 ₽, итого 3040 ₽
        await OpenCartAsync();

        await Page.GetByLabel("Промокод").FillAsync("WELCOME500");
        await Page.Locator("#promo button").ClickAsync();

        await AssertMoneyAsync("subtotal", 3040);
        await AssertMoneyAsync("discount", 500);
        await AssertMoneyAsync("total", 2540);
    }

    [Test]
    public async Task Empty_promo_code_resets_discount()
    {
        await AddProductAsync(1);
        await OpenCartAsync();

        await Page.GetByLabel("Промокод").FillAsync("SALE10");
        await Page.Locator("#promo button").ClickAsync();
        await Expect(Page.GetByTestId("discount")).ToBeVisibleAsync();

        await Page.GetByLabel("Промокод").FillAsync(string.Empty);
        await Page.Locator("#promo button").ClickAsync();

        await Expect(Page.GetByTestId("discount")).ToHaveCountAsync(0);
        await AssertMoneyAsync("total", 890);
    }

    [Test]
    public async Task Unknown_promo_shows_error()
    {
        await AddProductAsync(1);
        await OpenCartAsync();

        await Page.GetByLabel("Промокод").FillAsync("NOPE");
        await Page.Locator("#promo button").ClickAsync();

        await Expect(Page.Locator("#toast")).ToContainTextAsync("Промокод не найден");
        await AssertMoneyAsync("total", 890);
    }
}
