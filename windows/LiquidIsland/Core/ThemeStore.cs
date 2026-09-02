using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows.Media;

namespace LiquidIsland.Core;

/// <summary>
/// Читает тему с диска, отдаёт её интерфейсу и следит за правками файла.
/// </summary>
public sealed class ThemeStore
{
    public static ThemeStore Shared { get; } = new();

    public event Action? Changed;

    public IslandTheme Theme { get; private set; } = IslandTheme.Default;
    public string ConfigPath { get; }

    private readonly FileSystemWatcher? _watcher;
    private readonly JsonSerializerOptions _options = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    private ThemeStore()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "LiquidIsland");
        Directory.CreateDirectory(directory);
        ConfigPath = Path.Combine(directory, "theme.json");

        Theme = Read() ?? IslandTheme.Default;
        // Пишем всегда, а не только при первом запуске: так в файл попадают
        // ключи, появившиеся в новых версиях, и он остаётся полным описанием
        // настроек, а не огрызком от старой сборки.
        Write();

        _watcher = new FileSystemWatcher(directory, "theme.json")
        {
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName,
            EnableRaisingEvents = true
        };
        _watcher.Changed += (_, _) => Reload();
        _watcher.Created += (_, _) => Reload();
    }

    private DateTime _lastReload = DateTime.MinValue;

    private void Reload()
    {
        // Редакторы пишут файл в несколько приёмов, и на одну правку прилетает
        // пачка событий. Читаем не чаще раза в четверть секунды.
        if (DateTime.UtcNow - _lastReload < TimeSpan.FromMilliseconds(250)) return;
        _lastReload = DateTime.UtcNow;

        var fresh = Read();
        if (fresh is null) return;
        Theme = fresh;
        Changed?.Invoke();
    }

    public void Update(Action<IslandTheme> change)
    {
        change(Theme);
        Write();
        Changed?.Invoke();
    }

    public void Reset()
    {
        Theme = IslandTheme.Default;
        Write();
        Changed?.Invoke();
    }

    /// <summary>
    /// Читает файл, накладывая сохранённое поверх значений по умолчанию.
    /// </summary>
    /// <remarks>
    /// Прямой разбор ломается, как только в теме появляется новый ключ: в
    /// старом файле его нет, и все настройки пользователя молча заменяются
    /// умолчаниями. Так уже случалось в версии для macOS, поэтому здесь сразу
    /// слияние.
    /// </remarks>
    private IslandTheme? Read()
    {
        if (!File.Exists(ConfigPath)) return null;

        try
        {
            var storedText = File.ReadAllText(ConfigPath);
            if (JsonNode.Parse(storedText) is not JsonObject stored) return null;

            var defaults = JsonSerializer.SerializeToNode(IslandTheme.Default, _options) as JsonObject;
            if (defaults is null) return null;

            Merge(defaults, stored);
            return defaults.Deserialize<IslandTheme>(_options);
        }
        catch (Exception)
        {
            // Испорченный файл не повод падать: работаем на умолчаниях, а файл
            // перезапишется при первой же правке настроек.
            return null;
        }
    }

    private static void Merge(JsonObject target, JsonObject source)
    {
        foreach (var (key, value) in source)
        {
            if (value is JsonObject nested && target[key] is JsonObject baseObject)
            {
                Merge(baseObject, nested);
            }
            else
            {
                target[key] = value?.DeepClone();
            }
        }
    }

    private void Write()
    {
        try
        {
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(Theme, _options));
        }
        catch (IOException)
        {
            // Файл может быть занят редактором — не беда, запишем в другой раз.
        }
    }

    /// <summary>Цвет из строки вида #AARRGGBB.</summary>
    public static Color ParseColor(string value)
    {
        try
        {
            return (Color)ColorConverter.ConvertFromString(value)!;
        }
        catch (Exception)
        {
            return Colors.Black;
        }
    }

    public static SolidColorBrush Brush(string value) => new(ParseColor(value));
}
