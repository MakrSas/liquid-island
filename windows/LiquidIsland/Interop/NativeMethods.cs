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

    // --- Размытие под окном ---

    [StructLayout(LayoutKind.Sequential)]
    private struct AccentPolicy
    {
        public int AccentState;
        public int AccentFlags;
        public uint GradientColor;
        public int AnimationId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WindowCompositionAttributeData
    {
        public int Attribute;
        public IntPtr Data;
        public int SizeOfData;
    }

    [DllImport("user32.dll")]
    private static extern int SetWindowCompositionAttribute(
        IntPtr window, ref WindowCompositionAttributeData data);

    private const int AccentEnableAcrylicBlurBehind = 4;
    private const int AccentDisabled = 0;
    private const int WcaAccentPolicy = 19;

    /// <summary>
    /// Включает акрил под всем окном.
    /// </summary>
    /// <remarks>
    /// Размытие ложится под окно целиком, а не под его часть — как и на macOS,
    /// где стекло лежит под всей фигурой. Нужный вид даёт чёрный слой поверх:
    /// он непрозрачен сверху и растворяется книзу, открывая размытие только
    /// там, где нужно.
    ///
    /// Функция недокументированная, поэтому все вызовы обёрнуты: на сборке,
    /// где её нет, остров просто останется плотным.
    /// </remarks>
    public static void SetAcrylic(IntPtr window, bool enabled, uint tint)
    {
        try
        {
            var accent = new AccentPolicy
            {
                AccentState = enabled ? AccentEnableAcrylicBlurBehind : AccentDisabled,
                AccentFlags = 2,
                GradientColor = tint,
                AnimationId = 0
            };

            var size = Marshal.SizeOf(accent);
            var pointer = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(accent, pointer, false);
                var data = new WindowCompositionAttributeData
                {
                    Attribute = WcaAccentPolicy,
                    Data = pointer,
                    SizeOfData = size
                };
                SetWindowCompositionAttribute(window, ref data);
            }
            finally
            {
                Marshal.FreeHGlobal(pointer);
            }
        }
        catch (Exception)
        {
            // Нет функции — нет размытия. Остальное работает.
        }
    }
}
