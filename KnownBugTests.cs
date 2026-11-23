
namespace QaShop.E2E;

/// <summary>
/// Тесты-репродукции найденных дефектов. Они отключены атрибутом Ignore,
/// чтобы основной прогон был зелёным. Снимите Ignore, чтобы увидеть падение.
/// Подробности — в разделе «Найденные баги» README.md.
/// </summary>
public class KnownBugTests : ShopTestBase
{
    [Test]
    [Ignore("BUG-01: кнопка «+» на карточке товара не ограничена остатком. Снимите Ignore после исправления.")]
    public async Task BUG01_Product_page_plus_must_stop_at_stock_limit()
    {
        await OpenAsync("product/11"); // Чайник с гусиным носиком — остаток 3 шт.

        for (var i = 0; i < 5; i++)
        {
            await Page.Locator("#qty-plus").ClickAsync();
        }

        // Фактически значение станет 6, а сервер ответит 409 «В наличии только 3 шт.».
        await Expect(Page.Locator("#qty")).ToHaveValueAsync("3");
    }

    [Test]
    [Ignore("BUG-02: кнопка «+» в корзине активна на границе остатка и показывает ошибку вместо disabled.")]
    public async Task BUG02_Cart_plus_must_be_disabled_at_stock_limit()
    {
        await AddProductAsync(11);

        await OpenCartAsync();
        var row = Page.Locator("[data-testid='cart-row'][data-id='11']");
        await row.Locator("button[data-qty]").Last.ClickAsync();
        await row.Locator("button[data-qty]").Last.ClickAsync();

        // Третий клик пытается поставить 4 шт. и вызывает toast с ошибкой.
        await row.Locator("button[data-qty]").Last.ClickAsync();

        await Expect(Page.Locator("#toast")).ToHaveCountAsync(0);
    }

    [Test]
    [Ignore("BUG-03: POST /api/cart/items с qty=0 или нечисловым qty молча добавляет 1 шт. вместо 400.")]
    public async Task BUG03_Api_must_reject_zero_quantity()
    {
        var response = await Context.APIRequest.PostAsync(
            ShopConfig.Url("/api/cart/items"),
            new() { DataObject = new { productId = 1, qty = 0 } });

        // Фактически: 201 Created и qty=1 в корзине.
        Assert.That(response.Status, Is.EqualTo(400));
    }

    [Test]
    [Ignore("BUG-04: .form label { display: grid } перебивает [hidden], поэтому адрес виден при самовывозе.")]
    public async Task BUG04_Address_field_must_be_hidden_for_pickup()
    {
        await AddProductAsync(13);
        await OpenCheckoutAsync();

        await Page.Locator("input[name='delivery'][value='pickup']").CheckAsync();

        // Фактически label остаётся видимым, несмотря на атрибут hidden.
        await Expect(Page.Locator("#address-row")).ToBeHiddenAsync();
    }
}
