namespace QaShop.E2E;

public class CatalogTests : ShopTestBase
{
    [Test]
    public async Task Catalog_shows_products_and_filters_by_category()
    {
        await OpenAsync();

        await Expect(ProductCards).ToHaveCountAsync(16);

        await Page.GetByLabel("Категория").SelectOptionAsync("tea");
        await Expect(ProductCards).ToHaveCountAsync(3);
        await Expect(ProductCards.First).ToContainTextAsync("Чай Те Гуань Инь");

        await Page.GetByLabel("Категория").SelectOptionAsync("gear");
        await Expect(ProductCards).ToHaveCountAsync(5);
    }

    [Test]
    public async Task Search_finds_by_name_and_description_and_handles_empty_result()
    {
        await OpenAsync();

        await Page.GetByLabel("Поиск").FillAsync("Матча");
        await Expect(ProductCards).ToHaveCountAsync(1);
        await Expect(ProductCards.First).ToContainTextAsync("Матча церемониальная");

        // Поиск работает и по описанию.
        await Page.GetByLabel("Поиск").FillAsync("жасмина");
        await Expect(ProductCards.First).ToContainTextAsync("Кофе Эфиопия Иргачефф");

        await Page.GetByLabel("Поиск").FillAsync("нет-такого-товара");
        await Expect(Page.GetByTestId("empty-list")).ToBeVisibleAsync();
    }

    [Test]
    public async Task Sort_changes_order_by_price()
    {
        await OpenAsync();

        await Page.GetByLabel("Сортировка").SelectOptionAsync("price_asc");
        await Expect(ProductCards).ToHaveCountAsync(16);
        // В каталоге есть debounce 250 мс — ждём, пока пересортируется первый товар.
        await Expect(ProductCards.First.Locator(".price")).ToContainTextAsync("320");

        var prices = (await ProductCards.Locator(".price").AllTextContentsAsync())
            .Select(ParseMoney)
            .ToArray();
        Assert.That(prices, Is.EqualTo(prices.OrderBy(p => p).ToArray()));

        await Page.GetByLabel("Сортировка").SelectOptionAsync("price_desc");
        await Expect(ProductCards.First).ToContainTextAsync("Чайник с гусиным носиком");
    }

    [Test]
    public async Task Product_page_adds_selected_quantity_to_cart()
    {
        await OpenAsync("product/6");

        await Expect(Page.GetByTestId("product-page")).ToBeVisibleAsync();
        Assert.That(ParseMoney(await Page.GetByTestId("product-price").TextContentAsync()), Is.EqualTo(1750));

        await Page.Locator("#qty").FillAsync("2");
        await Page.Locator("#add").ClickAsync();

        await Expect(Page.GetByTestId("cart-count")).ToHaveTextAsync("2");
    }
}
