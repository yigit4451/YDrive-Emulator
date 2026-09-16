using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using SegaEmulator.Input;
using SegaEmulator.Models;
using SegaEmulator.Services;
using System.IO;
using Microsoft.Win32;
using System.IO.Compression;

namespace SegaEmulator.ViewModels;

public class SettingsViewModel : INotifyPropertyChanged
{
    private readonly Action _closeAction;
    
    // Copy of settings for editing
    private string _biosPath = "";
    private bool _showFps;
    private string _screenFilter = "None";
    private bool _tubeTvEffectEnabled;
    private string _controllerType = "3-Button";
    private string _audioSamplerate = "44100";
    private string _ym2612Emulation = "mame";
    private bool _sixButtonAuto;
    private bool _svpSupport;

    private bool _isBiosUPresent;
    private bool _isBiosEPresent;
    private bool _isBiosJPresent;
    private bool _isUploadBiosVisible = true;
    private bool _isAnyBiosPresent;
    private bool _biosModified;
    private readonly Dictionary<string, byte[]> _originalBiosFiles = new();

    public ControlsViewModel ControlsVM { get; }
    public bool IsSaved { get; private set; }

    // --- Properties ---
    public string BiosPath
    {
        get => _biosPath;
        set { _biosPath = value; OnPropertyChanged(); }
    }
    public bool ShowFps
    {
        get => _showFps;
        set { _showFps = value; OnPropertyChanged(); }
    }
    public string ScreenFilter
    {
        get => _screenFilter;
        set { _screenFilter = value; OnPropertyChanged(); }
    }
    public bool TubeTvEffectEnabled
    {
        get => _tubeTvEffectEnabled;
        set { _tubeTvEffectEnabled = value; OnPropertyChanged(); }
    }
    public string ControllerType
    {
        get => _controllerType;
        set { _controllerType = value; OnPropertyChanged(); }
    }
    public string AudioSamplerate
    {
        get => _audioSamplerate;
        set { _audioSamplerate = value; OnPropertyChanged(); }
    }
    public string Ym2612Emulation
    {
        get => _ym2612Emulation;
        set { _ym2612Emulation = value; OnPropertyChanged(); }
    }
    public bool SixButtonAuto
    {
        get => _sixButtonAuto;
        set { _sixButtonAuto = value; OnPropertyChanged(); }
    }
    public bool SvpSupport
    {
        get => _svpSupport;
        set { _svpSupport = value; OnPropertyChanged(); }
    }

    public bool IsBiosUPresent { get => _isBiosUPresent; set { _isBiosUPresent = value; OnPropertyChanged(); } }
    public bool IsBiosEPresent { get => _isBiosEPresent; set { _isBiosEPresent = value; OnPropertyChanged(); } }
    public bool IsBiosJPresent { get => _isBiosJPresent; set { _isBiosJPresent = value; OnPropertyChanged(); } }
    public bool IsUploadBiosVisible { get => _isUploadBiosVisible; set { _isUploadBiosVisible = value; OnPropertyChanged(); } }
    public bool IsAnyBiosPresent { get => _isAnyBiosPresent; set { _isAnyBiosPresent = value; OnPropertyChanged(); } }

    public ICommand UploadBiosCommand { get; }
    public ICommand DeleteAllBiosCommand { get; }

    public ICommand SaveCommand { get; }
    public ICommand CancelCommand { get; }

    public SettingsViewModel(Action closeAction, SegaEmulator.Input.InputManager inputManager)
    {
        _closeAction = closeAction;
        ControlsVM = new ControlsViewModel(inputManager, () => {});

        // Load current settings
        var current = SettingsManager.Instance.Current;
        BiosPath = current.BiosPath;
        ShowFps = current.ShowFps;
        ScreenFilter = current.ScreenFilter;
        TubeTvEffectEnabled = current.TubeTvEffectEnabled;
        ControllerType = current.ControllerType;
        AudioSamplerate = current.AudioSamplerate;
        Ym2612Emulation = current.Ym2612Emulation;
        SixButtonAuto = current.SixButtonAuto;
        SvpSupport = current.SvpSupport;

        SaveCommand = new RelayCommand(_ => Save());
        CancelCommand = new RelayCommand(_ => Cancel());

        UploadBiosCommand = new RelayCommand(_ => UploadBios());
        DeleteAllBiosCommand = new RelayCommand(_ => DeleteAllBios());

        CheckBiosFiles();
        StoreOriginalBiosFiles();
    }

    private void CheckBiosFiles()
    {
        string systemDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "system");
        IsBiosUPresent = File.Exists(Path.Combine(systemDir, "bios_CD_U.bin"));
        IsBiosEPresent = File.Exists(Path.Combine(systemDir, "bios_CD_E.bin"));
        IsBiosJPresent = File.Exists(Path.Combine(systemDir, "bios_CD_J.bin"));
        IsUploadBiosVisible = !(IsBiosUPresent && IsBiosEPresent && IsBiosJPresent);
        IsAnyBiosPresent = IsBiosUPresent || IsBiosEPresent || IsBiosJPresent;
    }

    private void StoreOriginalBiosFiles()
    {
        string systemDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "system");
        string[] files = { "bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin" };
        foreach (var f in files)
        {
            string path = Path.Combine(systemDir, f);
            if (File.Exists(path))
            {
                _originalBiosFiles[f] = File.ReadAllBytes(path);
            }
        }
    }

    public void RestoreBiosFiles()
    {
        if (!_biosModified) return;

        try
        {
            string systemDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "system");
            string[] files = { "bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin" };
            foreach (var f in files)
            {
                string path = Path.Combine(systemDir, f);
                if (_originalBiosFiles.TryGetValue(f, out byte[]? data) && data != null)
                {
                    File.WriteAllBytes(path, data);
                }
                else if (File.Exists(path))
                {
                    File.Delete(path);
                }
            }
            _biosModified = false;
            CheckBiosFiles();
        }
        catch { /* ignore */ }
    }

    private string GetMd5Hash(byte[] data)
    {
        using (var md5 = System.Security.Cryptography.MD5.Create())
        {
            byte[] hashBytes = md5.ComputeHash(data);
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLowerInvariant();
        }
    }

    private void ProcessBiosData(byte[] data, string fileName, string systemDir)
    {
        string hash = GetMd5Hash(data);
        string destName = null;

        if (hash == "8a0b3f811a052fc38849bfb186b3f4c7")
            destName = "bios_CD_U.bin";
        else if (hash == "e66f2a17e64177db8dbce07d121750a0")
            destName = "bios_CD_E.bin";
        else if (hash == "2e4130e9c57cb6521e3e5e7780be123c")
            destName = "bios_CD_J.bin";
        else
        {
            string lowerName = fileName.ToLowerInvariant();
            if (lowerName.Contains("usa") || lowerName.Contains("_u.") || lowerName.Contains("_u_") || lowerName.Contains("(u)"))
                destName = "bios_CD_U.bin";
            else if (lowerName.Contains("eur") || lowerName.Contains("_e.") || lowerName.Contains("_e_") || lowerName.Contains("(e)"))
                destName = "bios_CD_E.bin";
            else if (lowerName.Contains("jap") || lowerName.Contains("_jp") || lowerName.Contains("_j.") || lowerName.Contains("_j_") || lowerName.Contains("(j)"))
                destName = "bios_CD_J.bin";
        }

        if (destName != null)
        {
            File.WriteAllBytes(Path.Combine(systemDir, destName), data);
            _biosModified = true;
        }
    }

    private void UploadBios()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Lütfen BIOS dosyalarını seçin (.bin veya .zip)",
            Filter = "BIOS Dosyası|*.zip;*.bin|Tüm Dosyalar|*.*"
        };
        
        if (dialog.ShowDialog() == true)
        {
            try
            {
                string systemDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "system");
                Directory.CreateDirectory(systemDir);
                
                string ext = Path.GetExtension(dialog.FileName).ToLowerInvariant();
                if (ext == ".zip")
                {
                    using (ZipArchive archive = ZipFile.OpenRead(dialog.FileName))
                    {
                        foreach (ZipArchiveEntry entry in archive.Entries)
                        {
                            if (!entry.Name.ToLowerInvariant().EndsWith(".bin")) continue;
                            using (var ms = new MemoryStream())
                            using (var stream = entry.Open())
                            {
                                stream.CopyTo(ms);
                                ProcessBiosData(ms.ToArray(), entry.Name, systemDir);
                            }
                        }
                    }
                }
                else if (ext == ".bin")
                {
                    byte[] data = File.ReadAllBytes(dialog.FileName);
                    ProcessBiosData(data, Path.GetFileName(dialog.FileName), systemDir);
                }
            }
            catch { /* Ignore or log */ }
        }
        
        CheckBiosFiles();
    }

    private void DeleteAllBios()
    {
        if (!IsAnyBiosPresent) return;

        string title = System.Windows.Application.Current?.TryFindResource("Msg_DeleteAllBiosTitle") as string ?? "BIOS Dosyalarını Sil";
        string message = System.Windows.Application.Current?.TryFindResource("Msg_DeleteAllBiosConfirm") as string ?? "SEGA CD BIOS Dosyalarını silmek mi istiyorsunuz?";
        
        var result = System.Windows.MessageBox.Show(
            message, 
            title, 
            System.Windows.MessageBoxButton.YesNo, 
            System.Windows.MessageBoxImage.Warning);

        if (result == System.Windows.MessageBoxResult.Yes)
        {
            try
            {
                string systemDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "system");
                
                string pathU = Path.Combine(systemDir, "bios_CD_U.bin");
                if (File.Exists(pathU)) File.Delete(pathU);

                string pathE = Path.Combine(systemDir, "bios_CD_E.bin");
                if (File.Exists(pathE)) File.Delete(pathE);

                string pathJ = Path.Combine(systemDir, "bios_CD_J.bin");
                if (File.Exists(pathJ)) File.Delete(pathJ);

                _biosModified = true;
                CheckBiosFiles();
            }
            catch (Exception ex)
            {
                System.Windows.MessageBox.Show(
                    $"BIOS dosyaları silinirken bir hata oluştu:\n{ex.Message}", 
                    "Hata", 
                    System.Windows.MessageBoxButton.OK, 
                    System.Windows.MessageBoxImage.Error);
            }
        }
    }

    private void Save()
    {
        IsSaved = true;
        var current = SettingsManager.Instance.Current;
        current.BiosPath = BiosPath;
        current.ShowFps = ShowFps;
        current.ScreenFilter = ScreenFilter;
        current.TubeTvEffectEnabled = TubeTvEffectEnabled;
        current.ControllerType = ControllerType;
        current.AudioSamplerate = AudioSamplerate;
        current.Ym2612Emulation = Ym2612Emulation;
        current.SixButtonAuto = SixButtonAuto;
        current.SvpSupport = SvpSupport;

        // Save Controls
        ControlsVM.Save();

        // Save to disk and notify
        SettingsManager.Instance.SaveSettings();

        _closeAction();
    }

    private void Cancel()
    {
        _closeAction();
    }

    public bool HasChanges()
    {
        if (_biosModified) return true;
        
        var current = SettingsManager.Instance.Current;
        if (BiosPath != current.BiosPath) return true;
        if (ShowFps != current.ShowFps) return true;
        if (ScreenFilter != current.ScreenFilter) return true;
        if (TubeTvEffectEnabled != current.TubeTvEffectEnabled) return true;
        if (ControllerType != current.ControllerType) return true;
        if (AudioSamplerate != current.AudioSamplerate) return true;
        if (Ym2612Emulation != current.Ym2612Emulation) return true;
        if (SixButtonAuto != current.SixButtonAuto) return true;
        if (SvpSupport != current.SvpSupport) return true;
        
        return ControlsVM.HasChanges();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
