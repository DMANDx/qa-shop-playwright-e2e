
namespace QaShop.E2E;

public class AuthTests : ShopTestBase
{
    [Test]
    public async Task Register_logout_login_and_see_order_history()
    {
        var email = ShopConfig.UniqueEmail();
        const string password = "password123";
        const string name = "Анна Тест";

        await OpenAsync("register");
        await Page.Locator("input[name='name']").FillAsync(name);
        await Page.Locator("input[name='email']").FillAsync(email);
        await Page.Locator("input[name='password']").FillAsync(password);
        await Page.Locator("#auth button[type='submit']").ClickAsync();

        await Expect(Page.Locator("#user-name")).ToHaveTextAsync(name);
        await Expect(Page.Locator("#nav-orders")).ToBeVisibleAsync();
        await Expect(Page.Locator("#nav-login")).ToBeHiddenAsync();

        await Page.Locator("#nav-logout").ClickAsync();
        await Expect(Page.Locator("#nav-login")).ToBeVisibleAsync();
        await Expect(Page.Locator("#user-name")).ToBeHiddenAsync();
        // В обработчике выхода есть и hashchange, и явный вызов route() — ждём завершения обоих.
        await Expect(Page.Locator("main h1")).ToHaveTextAsync("Каталог");

        await OpenAsync("login");
        await Page.Locator("input[name='email']").FillAsync(email);
        await Page.Locator("input[name='password']").FillAsync(password);
        await Page.Locator("#auth button[type='submit']").ClickAsync();

        await Expect(Page.Locator("#user-name")).ToHaveTextAsync(name);

        // Заказ, оформленный после входа, должен попасть в историю пользователя.
        await AddProductAsync(12); // Сироп карамельный — 390 ₽
        var orderId = await PlaceOrderAsync(name, "+7 900 000-00-02", courier: false);

        await Page.Locator("#nav-orders").ClickAsync();
        await Expect(Page.GetByTestId("orders-table")).ToBeVisibleAsync();
        await Expect(Page.GetByTestId("order-row")).ToHaveCountAsync(1);
        await Expect(Page.GetByTestId("order-row")).ToContainTextAsync($"№{orderId}");
    }

    [Test]
    public async Task Registration_validates_fields_and_rejects_duplicate_email()
    {
        await OpenAsync("register");
        await Page.Locator("input[name='name']").FillAsync("А");
        await Page.Locator("input[name='email']").FillAsync("not-an-email");
        await Page.Locator("input[name='password']").FillAsync("123");
        await Page.Locator("#auth button[type='submit']").ClickAsync();

        await Expect(Page.Locator(".field-error[data-field='name']")).ToBeVisibleAsync();
        await Expect(Page.Locator(".field-error[data-field='email']")).ToBeVisibleAsync();
        await Expect(Page.Locator(".field-error[data-field='password']")).ToBeVisibleAsync();

        var email = ShopConfig.UniqueEmail();
        await Page.Locator("input[name='name']").FillAsync("Второй Тест");
        await Page.Locator("input[name='email']").FillAsync(email);
        await Page.Locator("input[name='password']").FillAsync("password123");
        await Page.Locator("#auth button[type='submit']").ClickAsync();
        await Expect(Page.Locator("#user-name")).ToHaveTextAsync("Второй Тест");

        await Page.Locator("#nav-logout").ClickAsync();
        await Expect(Page.Locator("main h1")).ToHaveTextAsync("Каталог");
        await OpenAsync("register");
        await Page.Locator("input[name='name']").FillAsync("Третий Тест");
        await Page.Locator("input[name='email']").FillAsync(email);
        await Page.Locator("input[name='password']").FillAsync("password123");
        await Page.Locator("#auth button[type='submit']").ClickAsync();

        await Expect(Page.Locator(".form-error")).ToContainTextAsync("уже зарегистрирован");
    }

    [Test]
    public async Task Login_with_wrong_password_shows_error()
    {
        var email = ShopConfig.UniqueEmail();

        await OpenAsync("register");
        await Page.Locator("input[name='name']").FillAsync("Пароль Тест");
        await Page.Locator("input[name='email']").FillAsync(email);
        await Page.Locator("input[name='password']").FillAsync("correct-password");
        await Page.Locator("#auth button[type='submit']").ClickAsync();
        await Expect(Page.Locator("#user-name")).ToHaveTextAsync("Пароль Тест");

        await Page.Locator("#nav-logout").ClickAsync();
        await Expect(Page.Locator("main h1")).ToHaveTextAsync("Каталог");
        await OpenAsync("login");
        await Page.Locator("input[name='email']").FillAsync(email);
        await Page.Locator("input[name='password']").FillAsync("wrong-password");
        await Page.Locator("#auth button[type='submit']").ClickAsync();

        await Expect(Page.Locator(".form-error")).ToContainTextAsync("Неверный e-mail или пароль");
        await Expect(Page.Locator("#nav-login")).ToBeVisibleAsync();
    }
}
