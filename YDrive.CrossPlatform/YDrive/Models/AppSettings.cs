using System.Text.Json.Serialization;

namespace YDrive.Models;

public class AppSettings
{
    // General & Emulation
    public bool IsGridView { get; set; } = true;
    public string BiosPath { get; set; } = "";
    public bool ShowFps { get; set; } = false;
    public string SelectedCore { get; set; } = "Genesis Plus GX (Önerilen)";
    
    // Sega CD BIOS Status
    public bool IsUsBiosLoaded { get; set; } = false;
    public bool IsEuBiosLoaded { get; set; } = false;
    public bool IsJpBiosLoaded { get; set; } = false;

    // Audio Settings
    // "22050", "44100", "48000"
    public string AudioSamplerate { get; set; } = "44100";
    public double AudioVolume { get; set; } = 1.0;
    
    // "mame" (Low Quality), "nuked" (High Quality)
    public string Ym2612Emulation { get; set; } = "mame";
    public bool SvpSupport { get; set; } = false;

    // Video & Display
    public string ScreenFilter { get; set; } = "None";
    public bool TubeTvEffectEnabled { get; set; } = false;

    // "Fit", "4:3", "Stretch"
    public string AspectRatio { get; set; } = "Fit";

    // Mobile / System Lifecycle
    public bool AutoSaveEnabled { get; set; } = true;
    public bool KeepScreenOn { get; set; } = true;
    public int FastForwardSpeed { get; set; } = 2;

    // --- Control Settings ---
    // "3-Button", "6-Button"
    public string ControllerType { get; set; } = "6-Button";

    // Mobile / Touch Controls
    public bool HapticFeedbackEnabled { get; set; } = true;
    public bool IsCustomPositioned { get; set; } = false;
    public int TouchLayoutVersion { get; set; } = 8;
    public double CustomLayoutScreenWidth { get; set; } = 0;
    public double CustomLayoutScreenHeight { get; set; } = 0;

    // --- Global Touch Control Settings ---
    public double TouchOpacity { get; set; } = 1.0;
    public double TouchScale { get; set; } = 1.0;
    // --- Sega Genesis 6-Button Arcade Right-Bottom Arc Layout ---
    public double TouchDPadX { get; set; } = 0;
    public double TouchDPadY { get; set; } = 0;
    
    public double TouchAX { get; set; } = 0;
    public double TouchAY { get; set; } = 0;
    
    public double TouchBX { get; set; } = 0;
    public double TouchBY { get; set; } = 0;
    
    public double TouchCX { get; set; } = 0;
    public double TouchCY { get; set; } = 0;
    
    public double TouchXX { get; set; } = 0;
    public double TouchXY { get; set; } = 0;
    
    public double TouchYX { get; set; } = 0;
    public double TouchYY { get; set; } = 0;
    
    public double TouchZX { get; set; } = 0;
    public double TouchZY { get; set; } = 0;
    
    public double TouchStartX { get; set; } = 0;
    public double TouchStartY { get; set; } = 0;

    // --- Per-Button Scale & Opacity ---
    public double TouchDPadScale { get; set; } = 1.0;
    public double TouchDPadOpacity { get; set; } = 0.65;
    public double TouchAScale { get; set; } = 1.0;
    public double TouchAOpacity { get; set; } = 0.65;
    public double TouchBScale { get; set; } = 1.0;
    public double TouchBOpacity { get; set; } = 0.65;
    public double TouchCScale { get; set; } = 1.0;
    public double TouchCOpacity { get; set; } = 0.65;
    public double TouchXScale { get; set; } = 1.0;
    public double TouchXOpacity { get; set; } = 0.65;
    public double TouchYScale { get; set; } = 1.0;
    public double TouchYOpacity { get; set; } = 0.65;
    public double TouchZScale { get; set; } = 1.0;
    public double TouchZOpacity { get; set; } = 0.65;
    public double TouchStartScale { get; set; } = 1.0;
    public double TouchStartOpacity { get; set; } = 0.65;
}
