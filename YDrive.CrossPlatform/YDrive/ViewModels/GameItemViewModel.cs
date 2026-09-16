using System;
using System.IO;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using YDrive.Models;
using YDrive.Services;
using Avalonia.Media.Imaging;

namespace YDrive.ViewModels;

public partial class GameItemViewModel : ViewModelBase
{
    private readonly GameItem _item;
    private readonly IPlatformService _platformService;
    private readonly Action<GameItemViewModel>? _launchAction;

    public Action<GameItemViewModel>? DeleteAction { get; set; }

    public GameItem Item => _item;

    public string RomPath => _item.RomPath;
    
    [ObservableProperty]
    private string _title;
    
    [ObservableProperty]
    private string? _developer;
    
    [ObservableProperty]
    private string? _releaseDate;
    
    [ObservableProperty]
    private string? _consoleName;
    
    [ObservableProperty]
    private Bitmap? _coverImage;
    
    [ObservableProperty]
    private bool _hasCover;

    public string LastPlayedText
    {
        get
        {
            if (_item.LastPlayedDate.HasValue)
                return $"Son: {_item.LastPlayedDate.Value:dd.MM.yyyy}";
            return $"Eklenme: {_item.AddedDate:dd.MM.yyyy}";
        }
    }
    
    public GameItemViewModel(GameItem item, IPlatformService platformService, Action<GameItemViewModel>? launchAction = null)
    {
        _item = item;
        _platformService = platformService;
        _launchAction = launchAction;
        
        _title = string.IsNullOrWhiteSpace(item.Title) ? "Bilinmeyen Oyun" : item.Title;
        _developer = string.IsNullOrWhiteSpace(item.Developer) ? "SEGA" : item.Developer;
        _releaseDate = item.ReleaseYear;
        _consoleName = string.IsNullOrWhiteSpace(item.ConsoleName) ? "SEGA Mega Drive" : item.ConsoleName;
        
        LoadCover();
    }
    
    public void LoadCover()
    {
        try
        {
            if (!string.IsNullOrEmpty(_item.CoverImagePath) && File.Exists(_item.CoverImagePath))
            {
                var oldImage = CoverImage;
                
                using (var stream = File.OpenRead(_item.CoverImagePath))
                {
                    CoverImage = Bitmap.DecodeToWidth(stream, 300);
                }
                HasCover = true;
                
                oldImage?.Dispose();
            }
            else
            {
                var oldImage = CoverImage;
                CoverImage = null;
                HasCover = false;
                oldImage?.Dispose();
            }
        }
        catch
        {
            var oldImage = CoverImage;
            CoverImage = null;
            HasCover = false;
            oldImage?.Dispose();
        }
    }

    [RelayCommand]
    public void OpenGame()
    {
        _item.LastPlayedDate = DateTime.Now;
        OnPropertyChanged(nameof(LastPlayedText));
        MainViewModel.Instance?.SaveLibrary();
        _launchAction?.Invoke(this);
    }

    [RelayCommand]
    private async Task LaunchAsync()
    {
        OpenGame();
        await Task.CompletedTask;
    }

    [RelayCommand]
    private void Rename()
    {
        MainViewModel.Instance?.StartRename(this);
    }

    [RelayCommand]
    private void Delete()
    {
        DeleteAction?.Invoke(this);
    }

    [RelayCommand]
    public async Task RefreshMetadataAsync()
    {
        try
        {
            await _platformService.ShowMessageAsync("TheGamesDB", $"{Title} için bilgiler ve kapak indiriliyor...");
            var metaService = new GameMetadataService();
            var meta = await metaService.FetchMetadataAsync(Title, _item.Id, _item.SystemType, true);
            if (meta != null)
            {
                if (!string.IsNullOrEmpty(meta.Developer) && meta.Developer != "Bilinmiyor")
                    Developer = meta.Developer;
                if (!string.IsNullOrEmpty(meta.ReleaseYear) && meta.ReleaseYear != "Bilinmiyor")
                    ReleaseDate = meta.ReleaseYear;
                if (!string.IsNullOrEmpty(meta.Summary))
                    _item.Summary = meta.Summary;
                if (!string.IsNullOrEmpty(meta.ArtworkPath) && File.Exists(meta.ArtworkPath))
                {
                    _item.CoverImagePath = meta.ArtworkPath;
                    LoadCover();
                }

                MainViewModel.Instance?.SaveLibrary();
                await _platformService.ShowMessageAsync("TheGamesDB", $"{Title} bilgileri güncellendi!");
            }
        }
        catch (Exception ex)
        {
            await _platformService.ShowMessageAsync("TheGamesDB Hata", ex.Message);
        }
    }

    [RelayCommand]
    private void ShowAbout()
    {
        if (MainViewModel.Instance != null)
        {
            MainViewModel.Instance.SelectedGame = this;
            MainViewModel.Instance.IsAboutVisible = true;
        }
    }

    [RelayCommand]
    private async Task ChangeCoverAsync()
    {
        var result = await _platformService.OpenFileDialogAsync("Kapak Seç", "Resimler|*.jpg;*.jpeg;*.png");
        if (result != null)
        {
            _item.CoverImagePath = result;
            LoadCover();
            MainViewModel.Instance?.SaveLibrary();
        }
    }

    [RelayCommand]
    private void ClearCover()
    {
        _item.CoverImagePath = string.Empty;
        LoadCover();
        MainViewModel.Instance?.SaveLibrary();
    }
}
