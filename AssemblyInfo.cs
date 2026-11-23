using NUnit.Framework;

// Тесты сбрасывают данные магазина через REST, поэтому не должны идти параллельно.
[assembly: NonParallelizable]
