namespace LiquidIsland.Core;

/// <summary>
/// Состояние острова. Те же три фазы, что и в версии для macOS: покой,
/// подсветка под курсором и раскрытая панель.
/// </summary>
public enum IslandPhase { Closed, Hovered, Expanded }
