using System.Text.Json.Serialization;

namespace SegaEmulator.Models;

public class AppSettings
{
    public bool IsGridView { get; set; } = true;
    // --- Genesis Plus GX Settings ---
    public string BiosPath { get; set; } = "";
    

    
    public bool ShowFps { get; set; } = false;

    // "22050", "44100", "48000"
    public string AudioSamplerate { get; set; } = "44100";
    
    // "mame" (Low Quality), "nuked" (High Quality)
    public string Ym2612Emulation { get; set; } = "mame";
    
    public bool SixButtonAuto { get; set; } = false;
    
    public bool SvpSupport { get; set; } = false;
    // "None", "CRT", "LCD"
    public string ScreenFilter { get; set; } = "None";
    
    public bool TubeTvEffectEnabled { get; set; } = false;

    // --- Control Settings ---
    // "3-Button", "6-Button"
    public string ControllerType { get; set; } = "3-Button";
}
