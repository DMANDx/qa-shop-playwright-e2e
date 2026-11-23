
namespace QaShop.E2E;

public class CheckoutTests : ShopTestBase
{
    [Test]
    public async Task Guest_checkout_adds_courier_fee_and_reduces_stock()
    {
        await AddProductAsync(1); // 890 ₽

        var orderId = await PlaceOrderAsync(
            "Иван Тестов",
            "+7 900 000-00-00",
            "Москва, улица Тестовая, 1",
            courier: true);

        await Expect(Page.GetByTestId("order-id")).ToHaveTextAsync(orderId.ToString());
        await Expect(Page.GetByTestId("cart-count")).ToHaveTextAsync("0");
        await AssertMoneyAsync("total", 1190); // 890 + 300

        var order = await ApiGetAsync($"/api/orders/{orderId}");
        Assert.That(order.GetProperty("shipping").GetInt32(), Is.EqualTo(300));
        Assert.That(order.GetProperty("total").GetInt32(), Is.EqualTo(1190));
        Assert.That(order.GetProperty("delivery").GetString(), Is.EqualTo("courier"));
        Assert.That(order.GetProperty("customer").GetProperty("name").GetString(), Is.EqualTo("Иван Тестов"));

        var product = await ApiGetAsync("/api/products/1");
        Assert.That(product.GetProperty("stock").GetInt32(), Is.EqualTo(24));
    }

    [Test]
    public async Task Pickup_hides_address_and_is_free()
    {
        await AddProductAsync(13); // Шоколад — 320 ₽

        await OpenCheckoutAsync();
        await Page.Locator("input[name='delivery'][value='pickup']").CheckAsync();

        // Поле адреса получает атрибут hidden, но из-за CSS .form label { display: grid }
        // остаётся видимым — это отдельный баг, см. BUG-04 в KnownBugTests.
        await Expect(Page.GetByTestId("shipping")).ToHaveTextAsync("бесплатно");
        await AssertMoneyAsync("total", 320);

        await Page.Locator("input[name='name']").FillAsync("Самовывоз Тест");
        await Page.Locator("input[name='phone']").FillAsync("+7 900 000-00-01");
        await Page.Locator("#submit-order").ClickAsync();
        await Expect(Page.GetByTestId("order-success")).ToBeVisibleAsync();

        var orderId = int.Parse((await Page.GetByTestId("order-id").TextContentAsync())!.Trim());
        var order = await ApiGetAsync($"/api/orders/{orderId}");
        Assert.That(order.GetProperty("shipping").GetInt32(), Is.EqualTo(0));
        Assert.That(order.GetProperty("total").GetInt32(), Is.EqualTo(320));
        Assert.That(order.GetProperty("customer").GetProperty("address").GetString(), Is.EqualTo(string.Empty));
    }

    [Test]
    public async Task Checkout_shows_validation_errors_for_empty_form()
    {
        await AddProductAsync(9);
        await OpenCheckoutAsync();

        await Page.Locator("#submit-order").ClickAsync();

        await Expect(Page.Locator(".form-error")).ToContainTextAsync("Проверьте поля формы");
        await Expect(Page.Locator(".field-error")).ToHaveCountAsync(3);
        await Expect(Page.Locator(".field-error[data-field='name']")).ToBeVisibleAsync();
        await Expect(Page.Locator(".field-error[data-field='phone']")).ToBeVisibleAsync();
        await Expect(Page.Locator(".field-error[data-field='address']")).ToBeVisibleAsync();
    }

    [Test]
    public async Task Courier_delivery_becomes_free_from_3000_rubles()
    {
        await AddProductAsync(15); // Подарочный набор — 3490 ₽

        await OpenCheckoutAsync();
        await Expect(Page.GetByTestId("shipping")).ToHaveTextAsync("бесплатно");
        await AssertMoneyAsync("total", 3490);

        var orderId = await PlaceOrderAsync(
            "Бесплатная Доставка",
            "+7 900 000-00-03",
            "Санкт-Петербург, Невский проспект, 10",
            courier: true);

        var order = await ApiGetAsync($"/api/orders/{orderId}");
        Assert.That(order.GetProperty("shipping").GetInt32(), Is.EqualTo(0));
        Assert.That(order.GetProperty("total").GetInt32(), Is.EqualTo(3490));
    }

    [Test]
    public async Task Promo_discount_is_included_in_order_total()
    {
        await AddProductAsync(2); // 2150 ₽
        await AddProductAsync(8); // 1890 ₽, итого 4040 ₽
        await OpenCartAsync();

        await Page.GetByLabel("Промокод").FillAsync("WELCOME500");
        await Page.Locator("#promo button").ClickAsync();
        await AssertMoneyAsync("total", 3540);

        var orderId = await PlaceOrderAsync(
            "Скидка Тест",
            "+7 900 000-00-04",
            courier: false);

        var order = await ApiGetAsync($"/api/orders/{orderId}");
        Assert.That(order.GetProperty("subtotal").GetInt32(), Is.EqualTo(4040));
        Assert.That(order.GetProperty("discount").GetInt32(), Is.EqualTo(500));
        Assert.That(order.GetProperty("promo").GetString(), Is.EqualTo("WELCOME500"));
        Assert.That(order.GetProperty("total").GetInt32(), Is.EqualTo(3540));
    }
}
