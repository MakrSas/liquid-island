using System.Diagnostics;
using System.Windows;
using LiquidIsland.Core;
using LiquidIsland.Media;
using LiquidIsland.Sensors;
using LiquidIsland.UI;
using Forms = System.Windows.Forms;
using Drawing = System.Drawing;

namespace LiquidIsland;

public partial class App : Application
{
    private readonly MediaHub _media = new();
    private readonly SystemHud _hud = new();
    private IslandWindow? _island;
    private Forms.NotifyIcon? _tray;

    protected override async void OnStartup(StartupEventArgs args)
    {
        base.OnStartup(args);

        _hud.Start();
        _island = new IslandWindow(_media, _hud);
        _island.Show();

        InstallTray();

        // Показать предупреждение о заряде принудительно — иначе его не
        // проверить, пока батарея не сядет.
        if (Environment.GetEnvironmentVariable("LIQUID_ISLAND_TEST_BATTERY") == "1")
        {
            _hud.TestLowBattery();
        }

        await _media.StartAsync();
    }

    private void InstallTray()
    {
        _tray = new Forms.NotifyIcon
        {
            Icon = Drawing.SystemIcons.Application,
            Visible = true,
            Text = "Liquid Island"
        };

        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Открыть theme.json", null, (_, _) =>
        {
            Process.Start(new ProcessStartInfo(ThemeStore.Shared.ConfigPath) { UseShellExecute = true });
        });
        menu.Items.Add("Сбросить оформление", null, (_, _) => ThemeStore.Shared.Reset());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Завершить", null, (_, _) => Shutdown());
        _tray.ContextMenuStrip = menu;
    }

    protected override void OnExit(ExitEventArgs args)
    {
        _media.Stop();
        _hud.Dispose();
        if (_tray is not null)
        {
            _tray.Visible = false;
            _tray.Dispose();
        }
        base.OnExit(args);
    }
}
