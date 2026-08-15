// ─────────────────────────────────────────────────────────────
//  InputManager.cs — Klavye girdisini SEGA gamepad'e eşleyen yönetici
//  Tuş basımlarını izler, libretro input callback'ine besleme yapar
// ─────────────────────────────────────────────────────────────

using System.IO;
using System.Text.Json;
using System.Windows.Input;
using SegaEmulator.Core;

namespace SegaEmulator.Input;

/// <summary>
/// Klavye tuşlarını SEGA pad butonlarına eşler.
/// Thread-safe olarak tuş durumlarını izler.
/// </summary>
public class InputManager
{
    private static readonly string SettingsFilePath = Path.Combine(Path.GetDirectoryName(Environment.ProcessPath) ?? AppDomain.CurrentDomain.BaseDirectory, "controls.json");

    // Tuş → Libretro buton eşlemesi (Player 1)
    private Dictionary<Key, RetroJoypadButton> _keyMap = new();

    // Player 2 kontrolleri
    private Dictionary<Key, RetroJoypadButton> _keyMapP2 = new();

    // Anlık tuş durumları (thread-safe)
    private readonly HashSet<Key> _pressedKeys = new();
    private readonly object _lock = new();

    public InputManager()
    {
        LoadSettings();
    }

    private void SetDefaultBindings()
    {
        _keyMap = new Dictionary<Key, RetroJoypadButton>
        {
            { Key.Up,     RetroJoypadButton.Up },
            { Key.Down,   RetroJoypadButton.Down },
            { Key.Left,   RetroJoypadButton.Left },
            { Key.Right,  RetroJoypadButton.Right },
            { Key.Z,      RetroJoypadButton.Y },      // SEGA A
            { Key.X,      RetroJoypadButton.B },      // SEGA B
            { Key.C,      RetroJoypadButton.A },      // SEGA C
            { Key.A,      RetroJoypadButton.L },      // SEGA X
            { Key.S,      RetroJoypadButton.X },      // SEGA Y
            { Key.D,      RetroJoypadButton.R },      // SEGA Z
            { Key.Return, RetroJoypadButton.Start },
            { Key.RightShift, RetroJoypadButton.Select }, // Mode
            { Key.LeftShift, RetroJoypadButton.Select },
        };

        _keyMapP2 = new Dictionary<Key, RetroJoypadButton>
        {
            { Key.NumPad8, RetroJoypadButton.Up },
            { Key.NumPad2, RetroJoypadButton.Down },
            { Key.NumPad4, RetroJoypadButton.Left },
            { Key.NumPad6, RetroJoypadButton.Right },
            { Key.NumPad1, RetroJoypadButton.Y },      // A
            { Key.NumPad3, RetroJoypadButton.B },      // B
            { Key.NumPad5, RetroJoypadButton.A },      // C
            { Key.NumPad0, RetroJoypadButton.Start },
        };
    }

    public void LoadSettings()
    {
        try
        {
            if (File.Exists(SettingsFilePath))
            {
                var json = File.ReadAllText(SettingsFilePath);
                var settings = JsonSerializer.Deserialize<ControlSettings>(json);
                if (settings != null && settings.Player1Map != null && settings.Player2Map != null)
                {
                    _keyMap = settings.Player1Map;
                    _keyMapP2 = settings.Player2Map;
                    return;
                }
            }
        }
        catch { /* Fallback to default */ }

        SetDefaultBindings();
    }

    public void SaveSettings(Dictionary<Key, RetroJoypadButton> p1, Dictionary<Key, RetroJoypadButton> p2)
    {
        _keyMap = new Dictionary<Key, RetroJoypadButton>(p1);
        _keyMapP2 = new Dictionary<Key, RetroJoypadButton>(p2);

        try
        {
            var settings = new ControlSettings { Player1Map = _keyMap, Player2Map = _keyMapP2 };
            var json = JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(SettingsFilePath, json);
        }
        catch { }
    }

    public Dictionary<Key, RetroJoypadButton> GetKeyMap(int playerIndex)
    {
        // playerIndex 0 → Player 1 (_keyMap), playerIndex 1 → Player 2 (_keyMapP2)
        return playerIndex == 0 ? new Dictionary<Key, RetroJoypadButton>(_keyMap)
                                : new Dictionary<Key, RetroJoypadButton>(_keyMapP2);
    }

    /// <summary>
    /// Tuş basma olayını kaydeder.
    /// </summary>
    public void KeyDown(Key key)
    {
        lock (_lock)
        {
            _pressedKeys.Add(key);
        }
    }

    /// <summary>
    /// Tuş bırakma olayını kaydeder.
    /// </summary>
    public void KeyUp(Key key)
    {
        lock (_lock)
        {
            _pressedKeys.Remove(key);
        }
    }

    /// <summary>
    /// Belirli bir tuşun basılı olup olmadığını sorgular.
    /// </summary>
    private bool IsKeyPressed(Key key)
    {
        lock (_lock)
        {
            return _pressedKeys.Contains(key);
        }
    }

    /// <summary>
    /// Libretro input state callback'ine yanıt verir.
    /// </summary>
    public short GetInputState(uint port, uint device, uint index, uint id)
    {
        if (device != RetroDevice.JOYPAD) return 0;

        var buttonId = (RetroJoypadButton)id;
        var keyMap = port == 0 ? _keyMap : _keyMapP2;

        foreach (var (key, button) in keyMap)
        {
            if (button == buttonId && IsKeyPressed(key))
                return 1;
        }

        return 0;
    }

    /// <summary>
    /// Tüm tuş durumlarını sıfırlar.
    /// </summary>
    public void Reset()
    {
        lock (_lock)
        {
            _pressedKeys.Clear();
        }
    }

    /// <summary>
    /// Varsayılan tuş eşlemesini metin olarak döndürür.
    /// </summary>
    public static string GetControlSchemeText()
    {
        return "Tuşlar 'Ayarlar > Kontrol Ayarları' menüsünden değiştirilebilir.";
    }
}

public class ControlSettings
{
    public Dictionary<Key, RetroJoypadButton> Player1Map { get; set; } = new();
    public Dictionary<Key, RetroJoypadButton> Player2Map { get; set; } = new();
}
