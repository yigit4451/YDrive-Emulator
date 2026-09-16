// ─────────────────────────────────────────────────────────────
//  InputManager.cs — Klavye ve Gamepad girdisini SEGA 6-Buton pad'e eşleyen yönetici
//  Sıfır gecikmeli (zero-latency) bitmask önbelleği ve cihaz kimliği desteği
// ─────────────────────────────────────────────────────────────

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using Avalonia.Input;
using YDrive.Core;

namespace YDrive.Input;

/// <summary>
/// Klavye ve Gamepad girişlerini SEGA 6-buton pad'e eşler.
/// Thread-safe ve sıfır kilit (lock-free) bitmask önbelleği ile çalışır.
/// </summary>
public enum InputMode
{
    MainMenu,
    InGame,
    GameOverlay
}

public class InputManager
{
    private static InputManager? _instance;
    public static InputManager Instance => _instance ??= new InputManager();

    public InputMode CurrentMode { get; set; } = InputMode.MainMenu;

    public static bool IsGameRunning => Instance.CurrentMode == InputMode.InGame;
    public static bool IsOverlayOpen => Instance.CurrentMode == InputMode.GameOverlay;

    public bool IsGamepadActive { get; set; }

    public event Action? OnGamepadActivity;
    public event Action? OnTopBarToggleRequested;

    public void NotifyGamepadActivity()
    {
        IsGamepadActive = true;
        OnGamepadActivity?.Invoke();
    }

    private static readonly string SettingsFilePath = GetInputSettingsPath();

    private static string GetInputSettingsPath()
    {
        try
        {
            var dir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrEmpty(dir))
                dir = AppDomain.CurrentDomain.BaseDirectory;
            return Path.Combine(dir, "ydrive_controls.json");
        }
        catch
        {
            return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ydrive_controls.json");
        }
    }

    // Tuş → Libretro buton eşlemesi
    private Dictionary<Avalonia.Input.Key, RetroJoypadButton> _keyMap = new();
    private Dictionary<Avalonia.Input.Key, RetroJoypadButton> _keyMapP2 = new();

    // Anlık tuş durumları
    private readonly HashSet<Avalonia.Input.Key> _pressedKeys = new();
    private readonly HashSet<RetroJoypadButton> _pressedGamepadButtonsP1 = new();
    private readonly object _lock = new();

    // O(1) atomik bitmask önbellekleri (Sıfır gecikme)
    private volatile int _bitmaskP1;
    private volatile int _bitmaskP2;

    // Analog (Joystick) anlık durumları (X, Y değerleri -0x8000 ile 0x7FFF arası)
    private volatile short _analogLeftXP1;
    private volatile short _analogLeftYP1;
    private volatile short _analogRightXP1;
    private volatile short _analogRightYP1;

    public InputManager()
    {
        LoadSettings();
    }

    private void SetDefaultBindings()
    {
        _keyMap = new Dictionary<Avalonia.Input.Key, RetroJoypadButton>
        {
            { Avalonia.Input.Key.Up,         RetroJoypadButton.Up },
            { Avalonia.Input.Key.Down,       RetroJoypadButton.Down },
            { Avalonia.Input.Key.Left,       RetroJoypadButton.Left },
            { Avalonia.Input.Key.Right,      RetroJoypadButton.Right },
            { Avalonia.Input.Key.Z,          RetroJoypadButton.Y },      // SEGA A
            { Avalonia.Input.Key.X,          RetroJoypadButton.B },      // SEGA B
            { Avalonia.Input.Key.C,          RetroJoypadButton.A },      // SEGA C
            { Avalonia.Input.Key.A,          RetroJoypadButton.L },      // SEGA X
            { Avalonia.Input.Key.S,          RetroJoypadButton.X },      // SEGA Y
            { Avalonia.Input.Key.D,          RetroJoypadButton.R },      // SEGA Z
            { Avalonia.Input.Key.Return,     RetroJoypadButton.Start },
            { Avalonia.Input.Key.RightShift, RetroJoypadButton.Select }, // Mode
            { Avalonia.Input.Key.LeftShift,  RetroJoypadButton.Select },
        };

        _keyMapP2 = new Dictionary<Avalonia.Input.Key, RetroJoypadButton>
        {
            { Avalonia.Input.Key.NumPad8, RetroJoypadButton.Up },
            { Avalonia.Input.Key.NumPad2, RetroJoypadButton.Down },
            { Avalonia.Input.Key.NumPad4, RetroJoypadButton.Left },
            { Avalonia.Input.Key.NumPad6, RetroJoypadButton.Right },
            { Avalonia.Input.Key.NumPad1, RetroJoypadButton.Y },      // SEGA A
            { Avalonia.Input.Key.NumPad3, RetroJoypadButton.B },      // SEGA B
            { Avalonia.Input.Key.NumPad5, RetroJoypadButton.A },      // SEGA C
            { Avalonia.Input.Key.NumPad7, RetroJoypadButton.L },      // SEGA X
            { Avalonia.Input.Key.NumPad9, RetroJoypadButton.X },      // SEGA Y
            { Avalonia.Input.Key.Add,     RetroJoypadButton.R },      // SEGA Z
            { Avalonia.Input.Key.NumPad0, RetroJoypadButton.Start },
            { Avalonia.Input.Key.Decimal, RetroJoypadButton.Select }  // Mode
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
        _keyMap = new Dictionary<Avalonia.Input.Key, RetroJoypadButton>
        {
            { Avalonia.Input.Key.Up,         RetroJoypadButton.Up },
            { Avalonia.Input.Key.Down,       RetroJoypadButton.Down },
            { Avalonia.Input.Key.Left,       RetroJoypadButton.Left },
            { Avalonia.Input.Key.Right,      RetroJoypadButton.Right },
            { Avalonia.Input.Key.Z,          RetroJoypadButton.Y },      // SEGA A
            { Avalonia.Input.Key.X,          RetroJoypadButton.B },      // SEGA B
            { Avalonia.Input.Key.C,          RetroJoypadButton.A },      // SEGA C
            { Avalonia.Input.Key.A,          RetroJoypadButton.L },      // SEGA X
            { Avalonia.Input.Key.S,          RetroJoypadButton.X },      // SEGA Y
            { Avalonia.Input.Key.D,          RetroJoypadButton.R },      // SEGA Z
            { Avalonia.Input.Key.Return,     RetroJoypadButton.Start },
            { Avalonia.Input.Key.RightShift, RetroJoypadButton.Select }, // Mode
            { Avalonia.Input.Key.LeftShift,  RetroJoypadButton.Select },
        };
    }

    private void SetDefaultKeyboardP2()
    {
        _keyMapP2 = new Dictionary<Avalonia.Input.Key, RetroJoypadButton>
        {
            { Avalonia.Input.Key.NumPad8, RetroJoypadButton.Up },
            { Avalonia.Input.Key.NumPad2, RetroJoypadButton.Down },
            { Avalonia.Input.Key.NumPad4, RetroJoypadButton.Left },
            { Avalonia.Input.Key.NumPad6, RetroJoypadButton.Right },
            { Avalonia.Input.Key.NumPad1, RetroJoypadButton.Y },      // SEGA A
            { Avalonia.Input.Key.NumPad3, RetroJoypadButton.B },      // SEGA B
            { Avalonia.Input.Key.NumPad5, RetroJoypadButton.A },      // SEGA C
            { Avalonia.Input.Key.NumPad7, RetroJoypadButton.L },      // SEGA X
            { Avalonia.Input.Key.NumPad9, RetroJoypadButton.X },      // SEGA Y
            { Avalonia.Input.Key.Add,     RetroJoypadButton.R },      // SEGA Z
            { Avalonia.Input.Key.NumPad0, RetroJoypadButton.Start },
            { Avalonia.Input.Key.Decimal, RetroJoypadButton.Select }  // Mode
        };
    }

    public void SaveSettings(Dictionary<Avalonia.Input.Key, RetroJoypadButton> p1, Dictionary<Avalonia.Input.Key, RetroJoypadButton> p2)
    {
        _keyMap = new Dictionary<Avalonia.Input.Key, RetroJoypadButton>(p1);
        _keyMapP2 = new Dictionary<Avalonia.Input.Key, RetroJoypadButton>(p2);

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

    public Dictionary<Avalonia.Input.Key, RetroJoypadButton> GetKeyMap(int playerIndex)
    {
        return playerIndex == 0 ? new Dictionary<Avalonia.Input.Key, RetroJoypadButton>(_keyMap)
                                : new Dictionary<Avalonia.Input.Key, RetroJoypadButton>(_keyMapP2);
    }

    /// <summary>
    /// Tuş basma olayını kaydeder ve bitmask'i anında günceller.
    /// </summary>
    public void KeyDown(Avalonia.Input.Key key)
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
    public void KeyUp(Avalonia.Input.Key key)
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

            foreach (var btn in _pressedGamepadButtonsP1)
            {
                maskP1 |= (1 << (int)btn);
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
        uint baseDevice = device & 0xFF;

        if (baseDevice == RetroDevice.ANALOG)
        {
            if (port != 0) return 0;

            if (index == RetroDeviceAnalog.RETRO_DEVICE_INDEX_ANALOG_LEFT)
            {
                if (id == RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_X) return _analogLeftXP1;
                if (id == RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_Y) return _analogLeftYP1;
            }
            else if (index == RetroDeviceAnalog.RETRO_DEVICE_INDEX_ANALOG_RIGHT)
            {
                if (id == RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_X) return _analogRightXP1;
                if (id == RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_Y) return _analogRightYP1;
            }
            return 0;
        }

        // Joypad veya Joypad Subclass (örn: 6-button MD pad 0x201)
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
        _analogLeftXP1 = 0;
        _analogLeftYP1 = 0;
        _analogRightXP1 = 0;
        _analogRightYP1 = 0;
    }

    /// <summary>
    /// Tüm tuş durumlarını sıfırlar (örneğin menüye geçildiğinde karakterin yürümeye devam etmemesi için).
    /// </summary>
    public void ClearAllInputs()
    {
        _bitmaskP1 = 0;
        _bitmaskP2 = 0;
        _analogLeftXP1 = 0;
        _analogLeftYP1 = 0;
        _analogRightXP1 = 0;
        _analogRightYP1 = 0;
    }

    /// <summary>
    /// UI üzerinden TopBar görünürlüğünü tetiklemek için kullanılır.
    /// </summary>
    public void RequestTopBarToggle()
    {
        OnTopBarToggleRequested?.Invoke();
    }

    public static string GetControlSchemeText()
    {
        return "Tuşlar ve kontrolcüler 'Ayarlar > Kontroller' menüsünden özelleştirilebilir.";
    }

    /// <summary>
    /// Native Gamepad/Joystick üzerinden gelen tuş durumunu kaydeder.
    /// </summary>
    public void SetGamepadButtonState(int playerIndex, RetroJoypadButton button, bool isPressed)
    {
        lock (_lock)
        {
            if (playerIndex == 0)
            {
                if (isPressed)
                {
                    _pressedGamepadButtonsP1.Add(button);
                    NotifyGamepadActivity(); // HUD solma animasyonu için bildir
                }
                else
                    _pressedGamepadButtonsP1.Remove(button);
            }
        }
        UpdateBitmaskFromCurrentState();
    }

    /// <summary>
    /// Native Gamepad/Joystick üzerinden gelen Analog durumunu kaydeder.
    /// Değer -0x8000 ile 0x7FFF arasında olmalıdır.
    /// </summary>
    public void SetGamepadAnalogState(int playerIndex, uint index, uint id, short value)
    {
        if (playerIndex != 0) return;
        
        if (index == RetroDeviceAnalog.RETRO_DEVICE_INDEX_ANALOG_LEFT)
        {
            if (id == RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_X) _analogLeftXP1 = value;
            else if (id == RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_Y) _analogLeftYP1 = value;
        }
        else if (index == RetroDeviceAnalog.RETRO_DEVICE_INDEX_ANALOG_RIGHT)
        {
            if (id == RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_X) _analogRightXP1 = value;
            else if (id == RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_Y) _analogRightYP1 = value;
        }

        if (Math.Abs(value) > 4000) 
            NotifyGamepadActivity();
    }
}

public class ControlSettings
{
    public Dictionary<Avalonia.Input.Key, RetroJoypadButton> Player1Map { get; set; } = new();
    public Dictionary<Avalonia.Input.Key, RetroJoypadButton> Player2Map { get; set; } = new();
}


