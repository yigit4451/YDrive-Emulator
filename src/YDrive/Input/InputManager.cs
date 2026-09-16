// ─────────────────────────────────────────────────────────────
//  InputManager.cs — Klavye ve Gamepad girdisini SEGA 6-Buton pad'e eşleyen yönetici
//  Sıfır gecikmeli (zero-latency) bitmask önbelleği ve cihaz kimliği desteği
// ─────────────────────────────────────────────────────────────

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Windows.Input;
using SegaEmulator.Core;

namespace SegaEmulator.Input;

/// <summary>
/// Klavye ve Gamepad girişlerini SEGA 6-buton pad'e eşler.
/// Thread-safe ve sıfır kilit (lock-free) bitmask önbelleği ile çalışır.
/// </summary>
public class InputManager
{
    private static readonly string SettingsFilePath = Path.Combine(Path.GetDirectoryName(Environment.ProcessPath) ?? AppDomain.CurrentDomain.BaseDirectory, "controls.json");

    // Tuş → Libretro buton eşlemesi
    private Dictionary<Key, RetroJoypadButton> _keyMap = new();
    private Dictionary<Key, RetroJoypadButton> _keyMapP2 = new();

    // Anlık tuş durumları
    private readonly HashSet<Key> _pressedKeys = new();
    private readonly object _lock = new();

    // O(1) atomik bitmask önbellekleri (Sıfır gecikme)
    private volatile int _bitmaskP1;
    private volatile int _bitmaskP2;

    public InputManager()
    {
        LoadSettings();
    }

    private void SetDefaultBindings()
    {
        _keyMap = new Dictionary<Key, RetroJoypadButton>
        {
            { Key.Up,         RetroJoypadButton.Up },
            { Key.Down,       RetroJoypadButton.Down },
            { Key.Left,       RetroJoypadButton.Left },
            { Key.Right,      RetroJoypadButton.Right },
            { Key.Z,          RetroJoypadButton.Y },      // SEGA A
            { Key.X,          RetroJoypadButton.B },      // SEGA B
            { Key.C,          RetroJoypadButton.A },      // SEGA C
            { Key.A,          RetroJoypadButton.L },      // SEGA X
            { Key.S,          RetroJoypadButton.X },      // SEGA Y
            { Key.D,          RetroJoypadButton.R },      // SEGA Z
            { Key.Return,     RetroJoypadButton.Start },
            { Key.RightShift, RetroJoypadButton.Select }, // Mode
            { Key.LeftShift,  RetroJoypadButton.Select },
        };

        _keyMapP2 = new Dictionary<Key, RetroJoypadButton>
        {
            { Key.NumPad8, RetroJoypadButton.Up },
            { Key.NumPad2, RetroJoypadButton.Down },
            { Key.NumPad4, RetroJoypadButton.Left },
            { Key.NumPad6, RetroJoypadButton.Right },
            { Key.NumPad1, RetroJoypadButton.Y },      // SEGA A
            { Key.NumPad3, RetroJoypadButton.B },      // SEGA B
            { Key.NumPad5, RetroJoypadButton.A },      // SEGA C
            { Key.NumPad7, RetroJoypadButton.L },      // SEGA X
            { Key.NumPad9, RetroJoypadButton.X },      // SEGA Y
            { Key.Add,     RetroJoypadButton.R },      // SEGA Z
            { Key.NumPad0, RetroJoypadButton.Start },
            { Key.Decimal, RetroJoypadButton.Select }  // Mode
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
                if (settings != null)
                {
                    if (settings.Player1Map != null && settings.Player1Map.Count > 0)
                        _keyMap = settings.Player1Map;
                    else
                        SetDefaultKeyboardP1();

                    if (settings.Player2Map != null && settings.Player2Map.Count > 0)
                        _keyMapP2 = settings.Player2Map;
                    else
                        SetDefaultKeyboardP2();

                    return;
                }
            }
        }
        catch { /* Fallback to default */ }

        SetDefaultBindings();
    }

    private void SetDefaultKeyboardP1()
    {
        _keyMap = new Dictionary<Key, RetroJoypadButton>
        {
            { Key.Up,         RetroJoypadButton.Up },
            { Key.Down,       RetroJoypadButton.Down },
            { Key.Left,       RetroJoypadButton.Left },
            { Key.Right,      RetroJoypadButton.Right },
            { Key.Z,          RetroJoypadButton.Y },      // SEGA A
            { Key.X,          RetroJoypadButton.B },      // SEGA B
            { Key.C,          RetroJoypadButton.A },      // SEGA C
            { Key.A,          RetroJoypadButton.L },      // SEGA X
            { Key.S,          RetroJoypadButton.X },      // SEGA Y
            { Key.D,          RetroJoypadButton.R },      // SEGA Z
            { Key.Return,     RetroJoypadButton.Start },
            { Key.RightShift, RetroJoypadButton.Select }, // Mode
            { Key.LeftShift,  RetroJoypadButton.Select },
        };
    }

    private void SetDefaultKeyboardP2()
    {
        _keyMapP2 = new Dictionary<Key, RetroJoypadButton>
        {
            { Key.NumPad8, RetroJoypadButton.Up },
            { Key.NumPad2, RetroJoypadButton.Down },
            { Key.NumPad4, RetroJoypadButton.Left },
            { Key.NumPad6, RetroJoypadButton.Right },
            { Key.NumPad1, RetroJoypadButton.Y },      // SEGA A
            { Key.NumPad3, RetroJoypadButton.B },      // SEGA B
            { Key.NumPad5, RetroJoypadButton.A },      // SEGA C
            { Key.NumPad7, RetroJoypadButton.L },      // SEGA X
            { Key.NumPad9, RetroJoypadButton.X },      // SEGA Y
            { Key.Add,     RetroJoypadButton.R },      // SEGA Z
            { Key.NumPad0, RetroJoypadButton.Start },
            { Key.Decimal, RetroJoypadButton.Select }  // Mode
        };
    }

    public void SaveSettings(Dictionary<Key, RetroJoypadButton> p1, Dictionary<Key, RetroJoypadButton> p2)
    {
        _keyMap = new Dictionary<Key, RetroJoypadButton>(p1);
        _keyMapP2 = new Dictionary<Key, RetroJoypadButton>(p2);

        try
        {
            var settings = new ControlSettings
            {
                Player1Map = _keyMap,
                Player2Map = _keyMapP2
            };
            var json = JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(SettingsFilePath, json);
        }
        catch { }
    }

    public Dictionary<Key, RetroJoypadButton> GetKeyMap(int playerIndex)
    {
        return playerIndex == 0 ? new Dictionary<Key, RetroJoypadButton>(_keyMap)
                                : new Dictionary<Key, RetroJoypadButton>(_keyMapP2);
    }

    /// <summary>
    /// Tuş basma olayını kaydeder ve bitmask'i anında günceller.
    /// </summary>
    public void KeyDown(Key key)
    {
        lock (_lock)
        {
            _pressedKeys.Add(key);
        }
        UpdateBitmaskFromCurrentState();
    }

    /// <summary>
    /// Tuş bırakma olayını kaydeder ve bitmask'i anında günceller.
    /// </summary>
    public void KeyUp(Key key)
    {
        lock (_lock)
        {
            _pressedKeys.Remove(key);
        }
        UpdateBitmaskFromCurrentState();
    }

    /// <summary>
    /// Libretro InputPoll callback'i sırasında her kare çağrılarak gamepad ve klavye durumunu önbelleğe alır.
    /// Sıfır gecikmeli (zero-latency) tepki sağlar.
    /// </summary>
    public void PollInput()
    {
        UpdateBitmaskFromCurrentState();
    }

    private void UpdateBitmaskFromCurrentState()
    {
        int maskP1 = 0;
        int maskP2 = 0;

        // 1. Klavye Durumları
        lock (_lock)
        {
            foreach (var (key, btn) in _keyMap)
            {
                if (_pressedKeys.Contains(key))
                {
                    maskP1 |= (1 << (int)btn);
                }
            }

            foreach (var (key, btn) in _keyMapP2)
            {
                if (_pressedKeys.Contains(key))
                {
                    maskP2 |= (1 << (int)btn);
                }
            }
        }

        _bitmaskP1 = maskP1;
        _bitmaskP2 = maskP2;
    }

    /// <summary>
    /// Libretro input state callback'ine O(1) sıfır kilitli yanıt verir.
    /// </summary>
    public short GetInputState(uint port, uint device, uint index, uint id)
    {
        // Joypad veya Joypad Subclass (örn: 6-button MD pad 0x201)
        uint baseDevice = device & 0xFF;
        if (baseDevice != RetroDevice.JOYPAD && device != RetroDevice.JOYPAD) return 0;

        int mask = (port == 0) ? _bitmaskP1 : _bitmaskP2;
        return (short)((mask & (1 << (int)id)) != 0 ? 1 : 0);
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
        _bitmaskP1 = 0;
        _bitmaskP2 = 0;
    }

    public static string GetControlSchemeText()
    {
        return "Tuşlar ve kontrolcüler 'Ayarlar > Kontroller' menüsünden özelleştirilebilir.";
    }
}

public class ControlSettings
{
    public Dictionary<Key, RetroJoypadButton> Player1Map { get; set; } = new();
    public Dictionary<Key, RetroJoypadButton> Player2Map { get; set; } = new();
}
