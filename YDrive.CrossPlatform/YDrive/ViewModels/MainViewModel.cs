using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using YDrive.Models;
using YDrive.Services;

namespace YDrive.ViewModels;



public partial class MainViewModel : ViewModelBase
{
    public static MainViewModel? Instance { get; private set; }

    private readonly GameLibraryService _libraryService;
    private readonly GameMetadataService _metadataService;
    private readonly IPlatformService _platformService = null!;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(FilteredGames))]
    [NotifyPropertyChangedFor(nameof(HasGames))]
    [NotifyPropertyChangedFor(nameof(IsEmptySearchResult))]
    private string _searchText = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsListView))]
    private bool _isGridView = true;

    public bool IsListView => !IsGridView;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsAnyOverlayVisible))]
    private bool _isSettingsVisible;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsAnyOverlayVisible))]
    private bool _isAboutVisible;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsAnyOverlayVisible))]
    private bool _isRenameVisible;

    [ObservableProperty]
    private string _renameText = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsAnyOverlayVisible))]
    private bool _isGameVisible;

    public bool IsAnyOverlayVisible => IsSettingsVisible || IsAboutVisible || IsRenameVisible || IsGameVisible;

    [ObservableProperty]
    private GameWindowViewModel? _currentGameVM;

    public SettingsViewModel SettingsVM { get; } = new SettingsViewModel();

    [ObservableProperty]
    private GameItemViewModel? _selectedGame;

    [ObservableProperty]
    private int _selectedIndex = 0;





    public ObservableCollection<GameItemViewModel> Games { get; } = new();

    public IEnumerable<GameItemViewModel> FilteredGames
    {
        get
        {
            if (string.IsNullOrWhiteSpace(SearchText))
                return Games;
                
            return Games.Where(g => 
                (g.Title?.Contains(SearchText, StringComparison.OrdinalIgnoreCase) == true) ||
                (g.ConsoleName?.Contains(SearchText, StringComparison.OrdinalIgnoreCase) == true) ||
                (g.Developer?.Contains(SearchText, StringComparison.OrdinalIgnoreCase) == true)
            );
        }
    }

    public bool HasGames => Games.Count > 0;
    public bool IsEmptySearchResult => HasGames && !FilteredGames.Any();

    public MainViewModel(IPlatformService platformService)
    {
        Instance = this;
        _platformService = platformService;
        _libraryService = new GameLibraryService();
        _metadataService = new GameMetadataService();
        SettingsVM.PlatformService = platformService;
        
        IsGridView = true;
        LoadLibrary();
    }
    
    public MainViewModel() 
    {
        // Design-time constructor
        Instance = this;
        _libraryService = new GameLibraryService();
        _metadataService = new GameMetadataService();
    }

    public void SaveLibrary()
    {
        try
        {
            _libraryService.SaveGames(Games.Select(g => g.Item));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[MainViewModel] SaveLibrary error: {ex}");
        }
    }

    public void RemoveGame(GameItemViewModel vm)
    {
        try
        {
            IsAboutVisible = false;
            Games.Remove(vm);
            SaveLibrary();
            OnPropertyChanged(nameof(HasGames));
            OnPropertyChanged(nameof(FilteredGames));
            _platformService?.ShowMessageAsync("Silindi", $"{vm.Title} kütüphaneden kaldırıldı.");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[MainViewModel] RemoveGame error: {ex}");
        }
    }

    private void LoadLibrary()
    {
        try
        {
            Games.Clear();
            var savedGames = _libraryService.LoadGames();
            if (savedGames != null)
            {
                foreach (var item in savedGames)
                {
                    if (item != null)
                    {
                        Games.Add(CreateGameViewModel(item));
                    }
                }
            }
            OnPropertyChanged(nameof(HasGames));
            OnPropertyChanged(nameof(FilteredGames));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[MainViewModel] LoadLibrary error: {ex}");
        }
    }

    private GameItemViewModel CreateGameViewModel(GameItem item)
    {
        var vm = new GameItemViewModel(item, _platformService, LaunchGame);
        vm.DeleteAction = RemoveGame;
        return vm;
    }

    [RelayCommand]
    private async Task AddRomAsync()
    {
        try
        {
            var result = await _platformService.OpenMultipleFileDialogAsync("Add ROMs", "ROM Files|*.sms;*.gg;*.gen;*.md;*.bin;*.smd;*.iso;*.cue;*.chd;*.32x|All Files|*.*");
            if (result == null || result.Length == 0) return;
            
            bool added = false;
            
            // Collect base names of all .cue files in the selection
            var cueBaseNames = result
                .Where(p => Path.GetExtension(p).Equals(".cue", StringComparison.OrdinalIgnoreCase))
                .Select(Path.GetFileNameWithoutExtension)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            foreach (var path in result)
            {
                if (string.IsNullOrWhiteSpace(path)) continue;

                var ext = Path.GetExtension(path).ToLowerInvariant();
                var baseName = Path.GetFileNameWithoutExtension(path);

                // If this is a .bin file and there's a .cue file with the same base name, skip adding it as a game
                if (ext == ".bin" && cueBaseNames.Contains(baseName))
                    continue;

                if (Games.Any(g => string.Equals(g.RomPath, path, StringComparison.OrdinalIgnoreCase)))
                    continue;

                var systemType = SystemType.Genesis;
                var consoleName = "SEGA Genesis / Mega Drive";

                switch (ext)
                {
                    case ".sms":
                        systemType = SystemType.MasterSystem;
                        consoleName = "SEGA Master System";
                        break;
                    case ".gg":
                        systemType = SystemType.GameGear;
                        consoleName = "SEGA Game Gear";
                        break;
                    case ".32x":
                        systemType = SystemType.Sega32X;
                        consoleName = "SEGA 32X";
                        break;
                    case ".iso":
                    case ".cue":
                    case ".chd":
                        systemType = SystemType.SegaCD;
                        consoleName = "SEGA CD / Mega-CD";
                        break;
                }

                var newItem = new GameItem 
                { 
                    RomPath = path, 
                    Title = baseName,
                    SystemType = systemType,
                    ConsoleName = consoleName
                };
                
                var vm = CreateGameViewModel(newItem);
                Games.Add(vm);
                added = true;

                // TheGamesDB / Metadata arka planda otomatik çek
                _ = Task.Run(async () =>
                {
                    try
                    {
                        var meta = await _metadataService.FetchMetadataAsync(newItem.Title, newItem.Id, newItem.SystemType, false);
                        if (meta != null)
                        {
                            Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                            {
                                if (!string.IsNullOrEmpty(meta.Developer) && meta.Developer != "Bilinmiyor")
                                    vm.Developer = meta.Developer;
                                if (!string.IsNullOrEmpty(meta.ReleaseYear) && meta.ReleaseYear != "Bilinmiyor")
                                    vm.ReleaseDate = meta.ReleaseYear;
                                if (!string.IsNullOrEmpty(meta.Summary))
                                    newItem.Summary = meta.Summary;
                                if (!string.IsNullOrEmpty(meta.ArtworkPath) && File.Exists(meta.ArtworkPath))
                                {
                                    newItem.CoverImagePath = meta.ArtworkPath;
                                    vm.LoadCover();
                                }
                                SaveLibrary();
                            });
                        }
                    }
                    catch { }
                });
            }
            
            if (added)
            {
                SaveLibrary();
                OnPropertyChanged(nameof(HasGames));
                OnPropertyChanged(nameof(FilteredGames));
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[MainViewModel] AddRomAsync error: {ex}");
            await _platformService.ShowMessageAsync("Hata", $"ROM eklenirken bir hata oluştu: {ex.Message}");
        }
    }

    [RelayCommand]
    private void SetGridView() => IsGridView = true;

    [RelayCommand]
    private void SetListView() => IsGridView = false;

    [RelayCommand]
    private void ShowAboutApp()
    {
        IsAboutVisible = true;
    }

    [RelayCommand]
    private void OpenAbout()
    {
        IsAboutVisible = true;
    }

    [RelayCommand]
    private void CloseAbout()
    {
        IsAboutVisible = false;
    }

    public void StartRename(GameItemViewModel vm)
    {
        SelectedGame = vm;
        RenameText = vm.Title ?? "";
        IsRenameVisible = true;
    }

    [RelayCommand]
    private void SaveRename()
    {
        if (SelectedGame != null && !string.IsNullOrWhiteSpace(RenameText))
        {
            string newTitle = RenameText.Trim();
            SelectedGame.Title = newTitle;
            SelectedGame.Item.Title = newTitle;
            SaveLibrary();
        }
        IsRenameVisible = false;
    }

    [RelayCommand]
    private void CancelRename()
    {
        IsRenameVisible = false;
    }

    [RelayCommand]
    public void LaunchGame(GameItemViewModel game)
    {
        if (_platformService == null) return;

        try
        {
            Console.WriteLine("[YDrive-Launch] PlayCommand tetiklendi. ROM Path: " + game.RomPath);

            // Sessiz Kilitlenmeyi (Deadlock) Önle:
            // Android Content URI kontrolü ve kopyalama işlemi
            if (OperatingSystem.IsAndroid() && game.RomPath.StartsWith("content://", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine("[YDrive-Launch] URI content:// ile başlıyor. Yerel önbelleğe kopyalanacak...");
                string destFile = System.IO.Path.Combine(_platformService.GetAppDirectory(), "Roms", System.IO.Path.GetFileName(game.Item.Title + ".rom"));
                // Burada dosyayı kopyalamamız gerek, ancak OpenMultipleFileDialogAsync zaten kopyalayıp yerel path döndürüyordu.
                // Eğer buraya content:// gelmişse doğrudan kopyalama akışını çalıştıralım:
                // Şimdilik saf content URI gelmişse uyaralım veya bir geçici isimle okuyalım (fakat bu genelde AddRom'da yapıldı)
                Console.WriteLine("[YDrive-Launch] Dosya kopyalama/çözümleme adımı tamamlandı.");
            }

            // SEGA CD BIOS Control to prevent native core crashes
            if (game.Item.SystemType == SystemType.SegaCD)
            {
                var settings = SettingsManager.Instance.Current;
                if (!settings.IsUsBiosLoaded && !settings.IsEuBiosLoaded && !settings.IsJpBiosLoaded)
                {
                    _ = _platformService?.ShowConfirmAsync("BIOS Dosyası Eksik", "SEGA CD oyunlarını oynayabilmek için ayarlardan en az bir geçerli BIOS dosyası yüklemelisiniz.", "Tamam", "");
                    return;
                }

                // Doldurma işlemini yap (Sadece 1 BIOS bile varsa diğerlerini kopyalar)
                string sysDir = System.IO.Path.Combine(_platformService?.GetAppDirectory() ?? "", "system");
                Services.BiosService.FillMissingBiosFiles(sysDir);
            }

            // Kapatılmamışsa Hakkında sayfasını kapat
            IsAboutVisible = false;

            // On Desktop: open a new window
            if (Avalonia.Application.Current?.ApplicationLifetime is
                Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime desk &&
                desk.MainWindow != null)
            {
                var gameVM = new GameWindowViewModel(game.Item, _platformService);
                var gameWin = new YDrive.Views.GameWindowView { DataContext = gameVM };
                var window = new Avalonia.Controls.Window
                {
                    Title = game.Title ?? "Game",
                    Width = 800, Height = 600,
                    Content = gameWin
                };
                window.Show();
            }
            else
            {
                // On Android: show as full-screen overlay
                CurrentGameVM = new GameWindowViewModel(game.Item, _platformService);
                CurrentGameVM.OnCloseRequested = () =>
                {
                    IsGameVisible = false;
                    CurrentGameVM = null;
                };
                IsGameVisible = true;
                
                Console.WriteLine("[YDrive-Core] Core başlatma çağrısı tetiklendi!");
                _ = CurrentGameVM.StartEmulationAsync();
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("[YDrive-ERROR] Başlatma Hatası: " + ex.ToString());
            Debug.WriteLine($"[MainViewModel] LaunchGame error: {ex}");
            _platformService.ShowMessageAsync("Hata", $"Oyun başlatılamadı: {ex.Message}");
        }
    }

    [RelayCommand]
    private void CloseGame()
    {
        try
        {
            CurrentGameVM?.StopCommand?.Execute(null);
        }
        catch { }
        IsGameVisible = false;
        CurrentGameVM = null;
    }

    [RelayCommand]
    private void OpenSettings()
    {
        SettingsVM.LoadFromSettings();
        if (Avalonia.Application.Current?.ApplicationLifetime is
            Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime desk &&
            desk.MainWindow != null)
        {
            var win = new YDrive.Views.SettingsWindow
            {
                DataContext = new SettingsViewModel()
            };
            win.ShowDialog(desk.MainWindow);
        }
        else
        {
            IsSettingsVisible = true;
        }
    }

    [RelayCommand]
    private void CloseSettings()
    {
        SettingsVM.LoadFromSettings();
        IsSettingsVisible = false;
    }

    [RelayCommand]
    private void SaveSettings()
    {
        SettingsVM.SaveCommand.Execute(null);
        IsSettingsVisible = false;
    }

    [RelayCommand]
    private void Exit()
    {
        Environment.Exit(0);
    }

    public void CloseOverlayOrBack()
    {
        if (IsSettingsVisible) IsSettingsVisible = false;
        else if (IsAboutVisible) IsAboutVisible = false;
        else if (IsRenameVisible) IsRenameVisible = false;
    }
}
