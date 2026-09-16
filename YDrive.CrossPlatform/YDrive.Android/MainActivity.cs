using System;
using Android.App;
using Android.Content.PM;
using Android.Views;
using Android.Util;
using Avalonia;
using Avalonia.Android;
using Avalonia.Controls;
using Avalonia.VisualTree;
using YDrive.Core;
using YDrive.Input;
using System.Linq;
using System.Collections.Generic;

namespace YDrive.Android;

[Activity(
    Label = "YDrive",
    Theme = "@style/MyTheme.NoActionBar",
    Icon = "@drawable/icon",
    MainLauncher = true,
    LaunchMode = LaunchMode.SingleTop,
    ScreenOrientation = ScreenOrientation.SensorLandscape,
    ConfigurationChanges = ConfigChanges.Orientation | ConfigChanges.ScreenSize | ConfigChanges.UiMode | ConfigChanges.ScreenLayout | ConfigChanges.Keyboard | ConfigChanges.KeyboardHidden | ConfigChanges.Navigation)]
public class MainActivity : AvaloniaMainActivity<YDrive.App>
{

    protected override void OnCreate(global::Android.OS.Bundle? savedInstanceState)
    {
        base.OnCreate(savedInstanceState);
        Log.Debug("YDriveInput", "[DEBUG-INPUT] YDrive Android Activity Created! BlueStacks/DualSense Test Started.");
        
        Window?.SetFlags(WindowManagerFlags.KeepScreenOn, WindowManagerFlags.KeepScreenOn);
        if (Window?.DecorView != null)
        {
            Window.DecorView.Focusable = true;
            Window.DecorView.FocusableInTouchMode = true;
            Window.DecorView.RequestFocus();
        }

        CheckAndNotifyInitialGamepad();
    }

    private void CheckAndNotifyInitialGamepad()
    {
        try
        {
            var deviceIds = InputDevice.GetDeviceIds();
            if (deviceIds != null)
            {
                foreach (var id in deviceIds)
                {
                    var device = InputDevice.GetDevice(id);
                    if (device != null)
                    {
                        if ((device.Sources & InputSourceType.Gamepad) == InputSourceType.Gamepad ||
                            (device.Sources & InputSourceType.Joystick) == InputSourceType.Joystick)
                        {
                            InputManager.Instance.NotifyGamepadActivity();
                            break;
                        }
                    }
                }
            }
        }
        catch { }
    }

    protected override AppBuilder CustomizeAppBuilder(AppBuilder builder)
    {
        YDrive.App.PlatformService = new AndroidPlatformService(this);
        return base.CustomizeAppBuilder(builder)
            .WithInterFont()
            .UseAndroid();
    }

    private bool IsAcceptKey(Keycode key) => key == Keycode.ButtonA || key == Keycode.Button1 || key == Keycode.DpadCenter;
    private bool IsCancelKey(Keycode key) => key == Keycode.ButtonB || key == Keycode.Button2 || key == Keycode.Back || key == Keycode.Escape;
    private bool IsSecondaryKey(Keycode key) => key == Keycode.ButtonX || key == Keycode.Button3;
    private bool IsTertiaryKey(Keycode key) => key == Keycode.ButtonY || key == Keycode.Button4;
    private bool IsMenuKey(Keycode key) => key == Keycode.ButtonSelect || key == Keycode.ButtonMode || key == Keycode.Menu || key == Keycode.MediaRecord;

    private RetroJoypadButton? MapKeyCodeToRetro(Keycode keyCode)
    {
        // Genesis B -> RetroPad B (LibretroConstants mapping)
        if (IsAcceptKey(keyCode)) return RetroJoypadButton.B;
        // Genesis A -> RetroPad Y
        if (IsSecondaryKey(keyCode)) return RetroJoypadButton.Y;
        // Genesis C -> RetroPad A
        if (IsCancelKey(keyCode)) return RetroJoypadButton.A;
        // Genesis X -> RetroPad L
        if (IsTertiaryKey(keyCode)) return RetroJoypadButton.L;
        
        if (keyCode == Keycode.ButtonStart) return RetroJoypadButton.Start;
        if (IsMenuKey(keyCode)) return RetroJoypadButton.Select;

        return keyCode switch
        {
            Keycode.ButtonL1 => RetroJoypadButton.L,
            Keycode.ButtonR1 => RetroJoypadButton.R,
            Keycode.ButtonL2 => RetroJoypadButton.L2,
            Keycode.ButtonR2 => RetroJoypadButton.R2,
            Keycode.ButtonThumbl => RetroJoypadButton.L3,
            Keycode.ButtonThumbr => RetroJoypadButton.R3,
            Keycode.DpadUp => RetroJoypadButton.Up,
            Keycode.DpadDown => RetroJoypadButton.Down,
            Keycode.DpadLeft => RetroJoypadButton.Left,
            Keycode.DpadRight => RetroJoypadButton.Right,
            _ => null
        };
    }

    public override bool OnKeyDown(Keycode keyCode, KeyEvent? e)
    {
        Log.Debug("YDriveInput", $"[DEBUG-INPUT] OnKeyDown -> KeyCode: {keyCode}");
        return base.OnKeyDown(keyCode, e);
    }

    public override bool OnKeyUp(Keycode keyCode, KeyEvent? e)
    {
        Log.Debug("YDriveInput", $"[DEBUG-INPUT] OnKeyUp -> KeyCode: {keyCode}");
        return base.OnKeyUp(keyCode, e);
    }

    public override bool DispatchKeyEvent(KeyEvent? e)
    {
        if (e == null) return base.DispatchKeyEvent(e);

        // [DEBUG-INPUT] BlueStacks ve fiziksel Gamepad testleri için detaylı log:
        Log.Debug("YDriveInput", $"[DEBUG-INPUT] DispatchKeyEvent -> KeyCode: {e.KeyCode} (Int: {(int)e.KeyCode}), Action: {e.Action}, Source: {e.Source}");

        var mode = InputManager.Instance.CurrentMode;

        // A) SHARE / CREATE / OPTIONS TUŞU KONTROLÜ
        if (IsMenuKey(e.KeyCode))
        {
            // Yalnızca oyun içi veya oyun menüsündeyken TopBar'ı tetikle
            if (mode == InputMode.InGame || mode == InputMode.GameOverlay)
            {
                if (e.Action == KeyEventActions.Down)
                {
                    InputManager.Instance.RequestTopBarToggle();
                }
                return true; // Sisteme veya Avalonia'ya kaptırma
            }
            // MainMenu'de ise base veya HandleMenuGamepadInput üzerinden devam edecek
        }

        // GameOverlay'deyken ButtonB (Circle / Back) ile menüyü kapatıp oyuna dön
        if (mode == InputMode.GameOverlay && IsCancelKey(e.KeyCode))
        {
            if (e.Action == KeyEventActions.Down)
            {
                InputManager.Instance.RequestTopBarToggle();
            }
            return true;
        }

        // B) OYUN MODU (InGame)
        if (mode == InputMode.InGame)
        {
            // Source'a bakmaksızın, haritalanmış bir gamepad tuşuysa DOĞRUDAN oyuna gönder
            // Bluetooth gamepad'ler sıklıkla Keyboard source ile gelir
            var btn = MapKeyCodeToRetro(e.KeyCode);
            if (btn != null)
            {
                if (e.Action == KeyEventActions.Down)
                    InputManager.Instance.SetGamepadButtonState(0, btn.Value, true);
                else if (e.Action == KeyEventActions.Up)
                    InputManager.Instance.SetGamepadButtonState(0, btn.Value, false);

                return true; // KESİNLİKLE true döndür, Avalonia'nın tuşu yutmasını engelle!
            }

            // Haritalanmamış ancak bariz gamepad kaynaklı bir tuşsa Avalonia'nın arayüzüne gitmesini engelle
            if ((e.Source & InputSourceType.Gamepad) == InputSourceType.Gamepad || (e.Source & InputSourceType.Joystick) == InputSourceType.Joystick)
            {
                if (e.KeyCode >= Keycode.ButtonA && e.KeyCode <= Keycode.ButtonZ)
                    return true;
            }

            return base.DispatchKeyEvent(e);
        }

        return base.DispatchKeyEvent(e);
    }

    public override bool DispatchGenericMotionEvent(MotionEvent? e)
    {
        if (e == null) return base.DispatchGenericMotionEvent(e);

        // [DEBUG-INPUT] Analog ve Hat değerlerini BlueStacks ve DualSense için logla:
        if (e.Action == MotionEventActions.Move)
        {
            float axisX = e.GetAxisValue(Axis.X);
            float axisY = e.GetAxisValue(Axis.Y);
            float axisZ = e.GetAxisValue(Axis.Z);
            float axisRz = e.GetAxisValue(Axis.Rz);
            float hatX = e.GetAxisValue(Axis.HatX);
            float hatY = e.GetAxisValue(Axis.HatY);
            float lTrigger = e.GetAxisValue(Axis.Ltrigger);
            float rTrigger = e.GetAxisValue(Axis.Rtrigger);
            
            // Log kirliliğini önlemek için sadece hareket varsa logla
            if (Math.Abs(axisX) > 0.1f || Math.Abs(axisY) > 0.1f || Math.Abs(axisZ) > 0.1f || Math.Abs(axisRz) > 0.1f || 
                Math.Abs(hatX) > 0.1f || Math.Abs(hatY) > 0.1f || lTrigger > 0.1f || rTrigger > 0.1f)
            {
                Log.Debug("YDriveInput", $"[DEBUG-INPUT] MotionEvent -> X:{axisX:F2} Y:{axisY:F2} | Z:{axisZ:F2} RZ:{axisRz:F2} | HatX:{hatX:F2} HatY:{hatY:F2} | LT:{lTrigger:F2} RT:{rTrigger:F2} | Source: {e.Source}");
            }
        }

        // InGame oyun modu — analog ve hat eksenlerini doğrudan Libretro'ya ilet
        if (InputManager.IsGameRunning && e.Action == MotionEventActions.Move)
        {
            float axisX = e.GetAxisValue(Axis.X);
            float axisY = e.GetAxisValue(Axis.Y);
            float axisZ = e.GetAxisValue(Axis.Z);
            float axisRz = e.GetAxisValue(Axis.Rz);
            float hatX = e.GetAxisValue(Axis.HatX);
            float hatY = e.GetAxisValue(Axis.HatY);
            float lTrigger = e.GetAxisValue(Axis.Ltrigger);
            float rTrigger = e.GetAxisValue(Axis.Rtrigger);

            short MapAnalog(float val)
            {
                if (Math.Abs(val) < 0.1f) return 0; // %10 deadzone
                return (short)(val * 32767f);
            }

            // Analog Çubuklar
            InputManager.Instance.SetGamepadAnalogState(0, RetroDeviceAnalog.RETRO_DEVICE_INDEX_ANALOG_LEFT, RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_X, MapAnalog(axisX));
            InputManager.Instance.SetGamepadAnalogState(0, RetroDeviceAnalog.RETRO_DEVICE_INDEX_ANALOG_LEFT, RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_Y, MapAnalog(axisY));
            InputManager.Instance.SetGamepadAnalogState(0, RetroDeviceAnalog.RETRO_DEVICE_INDEX_ANALOG_RIGHT, RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_X, MapAnalog(axisZ));
            InputManager.Instance.SetGamepadAnalogState(0, RetroDeviceAnalog.RETRO_DEVICE_INDEX_ANALOG_RIGHT, RetroDeviceAnalog.RETRO_DEVICE_ID_ANALOG_Y, MapAnalog(axisRz));

            // D-Pad Hat Kontrolleri (Bazı gamepad'ler D-Pad'i Hat olarak gönderir)
            InputManager.Instance.SetGamepadButtonState(0, RetroJoypadButton.Left, hatX < -0.5f);
            InputManager.Instance.SetGamepadButtonState(0, RetroJoypadButton.Right, hatX > 0.5f);
            InputManager.Instance.SetGamepadButtonState(0, RetroJoypadButton.Up, hatY < -0.5f);
            InputManager.Instance.SetGamepadButtonState(0, RetroJoypadButton.Down, hatY > 0.5f);

            // Trigger Kontrolleri (L2 / R2)
            InputManager.Instance.SetGamepadButtonState(0, RetroJoypadButton.L2, lTrigger > 0.5f);
            InputManager.Instance.SetGamepadButtonState(0, RetroJoypadButton.R2, rTrigger > 0.5f);

            return true;
        }

        return base.DispatchGenericMotionEvent(e);
    }


    public override bool DispatchTouchEvent(MotionEvent? e)
    {
        if (e != null)
        {
            // Kullanıcı ekrana dokunduğunda gamepad modundan çık
            if (InputManager.Instance.IsGamepadActive)
            {
                InputManager.Instance.IsGamepadActive = false;
            }
        }
        return base.DispatchTouchEvent(e);
    }
}
