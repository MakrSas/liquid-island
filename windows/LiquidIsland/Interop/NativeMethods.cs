using System.Runtime.InteropServices;

namespace LiquidIsland.Interop;

/// <summary>
/// Тонкая обвязка над Win32: окно поверх всех, сквозные клики и размытие.
/// </summary>
internal static class NativeMethods
{
    public const int GwlExStyle = -20;

    public const int WsExTransparent = 0x00000020;
    public const int WsExToolWindow = 0x00000080;
    public const int WsExNoActivate = 0x08000000;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr window, int index);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int SetWindowLong(IntPtr window, int index, int value);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int key);

    private const int VkLeftButton = 0x01;
    private const int VkRightButton = 0x02;

    /// <summary>
    /// Нажата ли сейчас кнопка мыши где угодно на экране.
    /// </summary>
    /// <remarks>
    /// Окно почти всё время сквозное и о чужих нажатиях не узнаёт, а свернуть
    /// раскрытый остров по клику мимо надо. Ставить перехватчик ради этого
    /// тяжело: состояние кнопки читается одним вызовом в том же такте, где мы
    /// и так следим за курсором.
    /// </remarks>
    public static bool IsMouseDown() =>
        (GetAsyncKeyState(VkLeftButton) & 0x8000) != 0
        || (GetAsyncKeyState(VkRightButton) & 0x8000) != 0;

    [StructLayout(LayoutKind.Sequential)]
    public struct Point
    {
        public int X;
        public int Y;
    }

    /// <summary>
    /// Делает окно сквозным для мыши или снова ловящим её.
    /// </summary>
    /// <remarks>
    /// Окно острова занимает широкую полосу вверху экрана, а перехватывать
    /// нажатия должно только там, где нарисована сама фигура. В версии для
    /// macOS ровно это решается переключением ignoresMouseEvents.
    /// </remarks>
    public static void SetClickThrough(IntPtr window, bool clickThrough)
    {
        var style = GetWindowLong(window, GwlExStyle);
        style = clickThrough ? style | WsExTransparent : style & ~WsExTransparent;
        SetWindowLong(window, GwlExStyle, style);
    }

    /// <summary>Убирает окно из панели задач и из переключателя окон.</summary>
    public static void HideFromTaskbar(IntPtr window)
    {
        var style = GetWindowLong(window, GwlExStyle);
        SetWindowLong(window, GwlExStyle, style | WsExToolWindow | WsExNoActivate);
    }
}
