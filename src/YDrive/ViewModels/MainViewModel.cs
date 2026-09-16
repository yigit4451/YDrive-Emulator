using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Data;
using System.Windows.Input;
using Microsoft.Win32;
using SegaEmulator.Helpers;
using SegaEmulator.Models;
using SegaEmulator.Services;

namespace SegaEmulator.ViewModels;

/// <summary>
/// Oyun Kütüphanesi (Launcher) Ana Penceresi için ViewModel.
/// ROM koleksiyonu, arama/filtreleme, görünüm modları ve diyalog işlemlerini yönetir.
/// </summary>
public class MainViewModel : INotifyPropertyChanged
{
    private readonly GameLibraryService _libraryService;
    private readonly GameMetadataService _metadataService;

    private string _searchText = string.Empty;
    private bool _isGridView = SettingsManager.Instance.Current.IsGridView;
    private GameItemViewModel? _selectedGame;

    public ObservableCollection<GameItemViewModel> Games { get; } = new();

    public ICollectionView FilteredGames { get; }

    public string SearchText
    {
        get => _searchText;
        set
        {
            if (SetField(ref _searchText, value))
            {
                FilteredGames.Refresh();
                OnPropertyChanged(nameof(HasGames));
                OnPropertyChanged(nameof(IsEmptySearchResult));
            }
        }
    }

    public bool IsGridView
    {
        get => _isGridView;
        set
        {
            if (SetField(ref _isGridView, value))
            {
                OnPropertyChanged(nameof(IsListView));
                SettingsManager.Instance.Current.IsGridView = value;
                SettingsManager.Instance.SaveSettings();
            }
        }
    }

    public bool IsListView
    {
        get => !_isGridView;
        set
        {
            if (_isGridView == value)
            {
                IsGridView = !value;
            }
        }
    }

    public GameItemViewModel? SelectedGame
    {
        get => _selectedGame;
        set => SetField(ref _selectedGame, value);
    }

    public bool HasGames => Games.Count > 0;
    public bool IsEmptySearchResult => HasGames && FilteredGames.Cast<object>().Count() == 0;

    // ──── Komutlar ────
    public ICommand AddRomCommand { get; }
    public ICommand SetGridViewCommand { get; }
    public ICommand SetListViewCommand { get; }
    public ICommand ShowAboutAppCommand { get; }
    public ICommand OpenSettingsCommand { get; }
    public ICommand ExitCommand { get; }

    public MainViewModel()
    {
        _libraryService = new GameLibraryService();
        _metadataService = new GameMetadataService();

        FilteredGames = CollectionViewSource.GetDefaultView(Games);
        FilteredGames.Filter = FilterGame;

        AddRomCommand       = new RelayCommand(_ => AddRom());
        SetGridViewCommand  = new RelayCommand(_ => IsGridView = true);
        SetListViewCommand  = new RelayCommand(_ => IsGridView = false);
        ShowAboutAppCommand = new RelayCommand(_ => ShowAboutApp());
        OpenSettingsCommand = new RelayCommand(_ => ShowSettings());
        ExitCommand         = new RelayCommand(_ => Application.Current.Shutdown());

        LoadLibrary();
    }

    private void LoadLibrary()
    {
        Games.Clear();
        var savedGames = _libraryService.LoadGames();

        foreach (var item in savedGames)
        {
            Games.Add(CreateGameViewModel(item));
        }

        OnPropertyChanged(nameof(HasGames));
        OnPropertyChanged(nameof(IsEmptySearchResult));
    }

    private GameItemViewModel CreateGameViewModel(GameItem item)
    {
        return new GameItemViewModel(
            item,
            onLaunch: LaunchGame,
            onRename: RenameGame,
            onShowAbout: ShowGameAbout,
            onDelete: DeleteGame,
            onChangeCover: ChangeCoverGame,
            onRemoveCover: RemoveCoverGame,
            onRescrape: RescrapeGame
        );
    }

    private bool FilterGame(object obj)
    {
        if (obj is not GameItemViewModel game) return false;
        if (string.IsNullOrWhiteSpace(SearchText)) return true;

        string search = SearchText.Trim();
        return game.Title.Contains(search, StringComparison.OrdinalIgnoreCase) ||
               game.ConsoleName.Contains(search, StringComparison.OrdinalIgnoreCase) ||
               game.Developer.Contains(search, StringComparison.OrdinalIgnoreCase);
    }

    public void AddRom()
    {
        var dialog = new OpenFileDialog
        {
            Title = (string)Application.Current.Resources["Dlg_AddRomTitle"],
            Filter = (string)Application.Current.Resources["Dlg_AddRomFilter"],
            Multiselect = true,
            CheckFileExists = true
        };

        if (dialog.ShowDialog() != true) return;

        string[] selectedFiles = dialog.FileNames;
        if (selectedFiles == null || selectedFiles.Length == 0) return;

        int addedCount = 0;
        int duplicateCount = 0;
        var newGamesToScrape = new List<(GameItemViewModel vm, GameItem item, string rawFileName)>();

        foreach (var romPath in selectedFiles)
        {
            if (string.IsNullOrWhiteSpace(romPath)) continue;

            // Zaten kütüphanede aynı ROM var mı kontrol et
            var existing = Games.FirstOrDefault(g => string.Equals(g.RomPath, romPath, StringComparison.OrdinalIgnoreCase));
            if (existing != null)
            {
                duplicateCount++;
                continue;
            }

            string rawFileName = Path.GetFileName(romPath);
            string cleanName = RomNameCleaner.CleanTitle(rawFileName);
            string ext = Path.GetExtension(romPath).ToLowerInvariant();

            SystemType sysType = ext switch
            {
                ".sms" => SystemType.MasterSystem,
                ".gg" => SystemType.GameGear,
                ".gen" or ".md" or ".bin" or ".smd" => SystemType.Genesis,
                ".iso" or ".cue" or ".chd" => SystemType.SegaCD,
                ".32x" => SystemType.Sega32X,
                _ => SystemType.Unknown
            };

            string consoleName = sysType switch
            {
                SystemType.MasterSystem => "SEGA Master System",
                SystemType.GameGear => "SEGA Game Gear",
                SystemType.Genesis => "SEGA Genesis / Mega Drive",
                SystemType.SegaCD => "SEGA CD",
                SystemType.Sega32X => "SEGA 32X",
                _ => "SEGA Genesis / Mega Drive"
            };

            var newItem = new GameItem
            {
                Title = cleanName,
                RomPath = romPath,
                SystemType = sysType,
                ConsoleName = consoleName,
                ReleaseYear = (string)Application.Current.Resources["Msg_Loading"],
                Developer = "SEGA",
                Summary = (string)Application.Current.Resources["Msg_MetadataLoading"],
                ArtworkPath = ""
            };

            var vm = CreateGameViewModel(newItem);
            Games.Add(vm);
            newGamesToScrape.Add((vm, newItem, rawFileName));
            addedCount++;
        }

        if (addedCount == 0 && duplicateCount > 0)
        {
            string msg = duplicateCount == 1
                ? (string)Application.Current.Resources["Msg_RomExists"]
                : (string)Application.Current.Resources["Msg_RomsAlreadyInLibrary"];
            string title = (string)Application.Current.Resources["Msg_Information"];
            MessageBox.Show(msg, title, MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        if (newGamesToScrape.Count == 0) return;

        SaveLibrary();

        FilteredGames.Refresh();

        if (SelectedGame == null || !Games.Contains(SelectedGame))
        {
            SelectedGame = newGamesToScrape[0].vm;
        }

        OnPropertyChanged(nameof(HasGames));
        OnPropertyChanged(nameof(IsEmptySearchResult));

        // Arka planda paralel (maksimum 3 eşzamanlı istek) metadata ve kapak resmi çekme
        Task.Run(async () =>
        {
            using var semaphore = new System.Threading.SemaphoreSlim(3);
            var tasks = newGamesToScrape.Select(async entry =>
            {
                await semaphore.WaitAsync();
                try
                {
                    var meta = await _metadataService.FetchMetadataAsync(entry.rawFileName, entry.vm.Id, entry.item.SystemType);
                    Application.Current?.Dispatcher?.Invoke(() =>
                    {
                        if (!string.IsNullOrEmpty(meta.Title) && meta.Title != entry.vm.Title)
                            entry.vm.Title = meta.Title;

                        if (!string.IsNullOrEmpty(meta.ReleaseYear) && meta.ReleaseYear != "Bilinmiyor")
                            entry.vm.ReleaseYear = meta.ReleaseYear;
                        else if (entry.vm.ReleaseYear == (string)Application.Current.Resources["Msg_Loading"])
                            entry.vm.ReleaseYear = "Bilinmiyor";

                        if (!string.IsNullOrEmpty(meta.Developer) && meta.Developer != "Bilinmiyor")
                            entry.vm.Developer = meta.Developer;

                        if (!string.IsNullOrEmpty(meta.Summary))
                            entry.vm.Summary = meta.Summary;

                        if (!string.IsNullOrEmpty(meta.ArtworkPath))
                        {
                            entry.vm.CoverImagePath = meta.ArtworkPath;
                            entry.vm.ArtworkPath = meta.ArtworkPath;
                        }

                        SaveLibrary();
                    });
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[Scraper] Hata ({entry.rawFileName}): {ex.Message}");
                }
                finally
                {
                    semaphore.Release();
                }
            });

            await Task.WhenAll(tasks);
        });
    }

    public void LaunchGame(GameItemViewModel game)
    {
        if (game == null) return;

        if (string.IsNullOrWhiteSpace(game.RomPath) || !File.Exists(game.RomPath))
        {
            string msg = string.Format((string)Application.Current.Resources["Msg_RomNotFoundAsk"], game.Title);
            string title = (string)Application.Current.Resources["Msg_RomNotFoundTitle"];
            var result = MessageBox.Show(msg, title, MessageBoxButton.YesNo, MessageBoxImage.Warning);

            if (result == MessageBoxResult.Yes)
            {
                var dialog = new OpenFileDialog
                {
                    Title = string.Format((string)Application.Current.Resources["Dlg_SelectRomForGame"], game.Title),
                    Filter = (string)Application.Current.Resources["Dlg_SelectRomFilter"],
                    CheckFileExists = true
                };

                if (dialog.ShowDialog() == true)
                {
                    game.RomPath = dialog.FileName;
                    SaveLibrary();
                }
                else
                {
                    return;
                }
            }
            else
            {
                return;
            }
        }

        try
        {
            var gameWindow = new SegaEmulator.Views.GameWindow();
            var gameViewModel = new GameWindowViewModel(game.Model);
            gameWindow.DataContext = gameViewModel;
            gameWindow.Show();
        }
        catch (Exception ex)
        {
            string msg = (string)Application.Current.Resources["Msg_RomAddError"] + ex.Message;
            string title = (string)Application.Current.Resources["Msg_Error"];
            var result = MessageBox.Show(msg, title, MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    public void RenameGame(GameItemViewModel game)
    {
        if (game == null) return;

        var renameDialog = new SegaEmulator.Views.RenameGameDialog(game.Title)
        {
            Owner = Application.Current.MainWindow
        };

        if (renameDialog.ShowDialog() == true && !string.IsNullOrWhiteSpace(renameDialog.NewTitle))
        {
            game.Title = renameDialog.NewTitle.Trim();
            SaveLibrary();
            FilteredGames.Refresh();
        }
    }

    public void ShowGameAbout(GameItemViewModel game)
    {
        if (game == null) return;

        var aboutWindow = new SegaEmulator.Views.GameDetailsWindow(game)
        {
            Owner = Application.Current.MainWindow
        };
        aboutWindow.ShowDialog();
    }

    public void ChangeCoverGame(GameItemViewModel game)
    {
        if (game == null) return;

        var dialog = new OpenFileDialog
        {
            Title = string.Format((string)Application.Current.Resources["Dlg_SelectCoverTitle"], game.Title),
            Filter = (string)Application.Current.Resources["Dlg_ImageFilter"],
            CheckFileExists = true
        };

        if (dialog.ShowDialog() == true)
        {
            string savedPath = _metadataService.SaveCustomCoverImage(dialog.FileName, game.Id);
            game.CoverImagePath = savedPath;
            game.ArtworkPath = savedPath;
            SaveLibrary();
        }
    }

    public void RemoveCoverGame(GameItemViewModel game)
    {
        if (game == null) return;

        string msg = string.Format((string)Application.Current.Resources["Msg_RemoveCoverConfirm"], game.Title);
        string title = (string)Application.Current.Resources["Msg_RemoveCoverTitle"];
        var confirm = MessageBox.Show(msg, title, MessageBoxButton.YesNo, MessageBoxImage.Question);

        if (confirm == MessageBoxResult.Yes)
        {
            game.CoverImagePath = string.Empty;
            game.ArtworkPath = string.Empty;
            SaveLibrary();
        }
    }

    public void DeleteGame(GameItemViewModel game)
    {
        if (game == null) return;

        string msg = string.Format((string)Application.Current.Resources["Msg_DeleteConfirm"], game.Title);
        string title = (string)Application.Current.Resources["Msg_DeleteConfirmTitle"];
        var confirm = MessageBox.Show(msg, title, MessageBoxButton.YesNo, MessageBoxImage.Question);

        if (confirm == MessageBoxResult.Yes)
        {
            Games.Remove(game);
            SaveLibrary();
            OnPropertyChanged(nameof(HasGames));
            OnPropertyChanged(nameof(IsEmptySearchResult));
        }
    }

    public void SaveLibrary()
    {
        _libraryService.SaveGames(Games.Select(g => g.Model));
    }

    private void ShowSettings()
    {
        var settingsWindow = new SegaEmulator.Views.SettingsWindow();
        var inputManager = new SegaEmulator.Input.InputManager();
        var vm = new SettingsViewModel(
            () => settingsWindow.Close(), 
            inputManager
        );
        settingsWindow.DataContext = vm;
        settingsWindow.Owner = Application.Current.MainWindow;
        settingsWindow.ShowDialog();
    }

    private void ShowAboutApp()
    {
        string msg = (string)Application.Current.Resources["Msg_AboutInfo"];
        string title = (string)Application.Current.Resources["Msg_AboutTitle"];
        MessageBox.Show(msg, title, MessageBoxButton.OK, MessageBoxImage.Information);
    }

    public async void RescrapeGame(GameItemViewModel game)
    {
        if (game == null || string.IsNullOrWhiteSpace(game.RomPath)) return;

        // Bilgileri temizlerken 'Yükleniyor...' göster
        string loadingText = (string)Application.Current.Resources["Msg_Loading"];
        game.ReleaseYear = loadingText;
        game.Developer = loadingText;
        game.Summary = loadingText;

        var rawFileName = Path.GetFileName(game.RomPath);

        // FetchMetadataAsync içinde CleanTitle çağrıldığı için "(USA)", ".bin" vb. otomatik temizlenir.
        var meta = await _metadataService.FetchMetadataAsync(rawFileName, game.Id, game.SystemType, true);

        App.Current.Dispatcher.Invoke(() =>
        {
            if (meta != null)
            {
                if (!string.IsNullOrEmpty(meta.Title))
                    game.Title = meta.Title;

                if (!string.IsNullOrEmpty(meta.ReleaseYear) && meta.ReleaseYear != "Bilinmiyor")
                    game.ReleaseYear = meta.ReleaseYear;
                else
                    game.ReleaseYear = "Bilinmiyor";

                if (!string.IsNullOrEmpty(meta.Developer) && meta.Developer != "Bilinmiyor")
                    game.Developer = meta.Developer;
                else
                    game.Developer = "Bilinmiyor";

                if (!string.IsNullOrEmpty(meta.Summary))
                    game.Summary = meta.Summary;
                else
                    game.Summary = "";

                if (!string.IsNullOrEmpty(meta.ArtworkPath))
                {
                    game.CoverImagePath = meta.ArtworkPath;
                    game.ArtworkPath = meta.ArtworkPath;
                }

                SaveLibrary();
            }
        });
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(name);
        return true;
    }
}
