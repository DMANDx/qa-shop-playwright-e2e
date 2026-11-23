namespace QaShop.E2E;

/// <summary>Общая конфигурация прогона тестов.</summary>
public static class ShopConfig
{
    /// <summary>Адрес магазина. Переопределяется переменной SHOP_BASE_URL.</summary>
    public static string BaseUrl { get; } =
        (Environment.GetEnvironmentVariable("SHOP_BASE_URL") ?? "http://localhost:3000").TrimEnd('/');

    public static string Url(string path)
    {
        var cleanPath = path.StartsWith('/') ? path : "/" + path;
        return BaseUrl + cleanPath;
    }

    /// <summary>
    /// localtunnel показывает одностраничное предупреждение для браузерных User-Agent.
    /// Заголовок allow-list'а позволяет тестам пройти через туннель без ручного подтверждения.
    /// Для обычного localhost заголовок безвреден.
    /// </summary>
    public static Dictionary<string, string> ExtraHeaders { get; } = new()
    {
        ["bypass-tunnel-reminder"] = "1",
    };

    public static string UniqueEmail() => $"e2e-{Guid.NewGuid():N}@example.com";
}
