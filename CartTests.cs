
namespace QaShop.E2E;

public class CartTests : ShopTestBase
{
    [Test]
    public async Task Cart_updates_quantity_removes_and_clears_items()
    {
        await AddProductAsync(1); // Кофе Эфиопия — 890 ₽
        await AddProductAsync(4); // Чай Те Гуань Инь — 640 ₽

        await Expect(Page.GetByTestId("cart-count")).ToHaveTextAsync("2");

        await OpenCartAsync();
        await Expect(Page.GetByTestId("cart-row")).ToHaveCountAsync(2);
        await AssertMoneyAsync("subtotal", 1530);

        var coffeeRow = Page.Locator("[data-testid='cart-row'][data-id='1']");
        await coffeeRow.Locator("input").FillAsync("3");
        // front-end слушает change, который срабатывает после потери фокуса
        await coffeeRow.Locator("input").PressAsync("Tab");
        await AssertMoneyAsync("subtotal", 3310); // 890*3 + 640
        await Expect(Page.GetByTestId("cart-count")).ToHaveTextAsync("4");

        var teaRow = Page.Locator("[data-testid='cart-row'][data-id='4']");
        await teaRow.GetByText("Удалить").ClickAsync();
        await Expect(Page.GetByTestId("cart-row")).ToHaveCountAsync(1);
        await AssertMoneyAsync("subtotal", 2670);
        await Expect(Page.GetByTestId("cart-count")).ToHaveTextAsync("3");

        await Page.Locator("#clear").ClickAsync();
        await Expect(Page.GetByTestId("cart-empty")).ToBeVisibleAsync();
        await Expect(Page.GetByTestId("cart-count")).ToHaveTextAsync("0");
    }

    [Test]
    public async Task Cart_rejects_quantity_above_stock_with_error_toast()
    {
        await AddProductAsync(11); // Чайник с гусиным носиком — в наличии 3 шт.

        await OpenCartAsync();
        var row = Page.Locator("[data-testid='cart-row'][data-id='11']");

        await row.Locator("button[data-qty]").Last.ClickAsync();
        await Expect(row.Locator("input")).ToHaveValueAsync("2");

        await row.Locator("button[data-qty]").Last.ClickAsync();
        await Expect(row.Locator("input")).ToHaveValueAsync("3");

        // Четвёртый клик должен быть отклонён сервером, а значение — остаться 3.
        await row.Locator("button[data-qty]").Last.ClickAsync();
        await Expect(Page.Locator("#toast")).ToContainTextAsync("В наличии только 3 шт.");
        await Expect(row.Locator("input")).ToHaveValueAsync("3");
    }
}
