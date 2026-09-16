using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using SegaEmulator.Models;

namespace SegaEmulator.ViewModels;

/// <summary>
/// Arayüzde Oyun Kartı olarak gösterilen tek bir oyunun ViewModel'i.
/// </summary>
public class GameItemViewModel : INotifyPropertyChanged
{
    private readonly GameItem _model;
    private readonly Action<GameItemViewModel> _onLaunch;
    private readonly Action<GameItemViewModel> _onRename;
    private readonly Action<GameItemViewModel> _onShowAbout;
    private readonly Action<GameItemViewModel>? _onDelete;
    private readonly Action<GameItemViewModel>? _onChangeCover;
    private readonly Action<GameItemViewModel>? _onRemoveCover;
    private readonly Action<GameItemViewModel>? _onRescrape;

    public GameItem Model => _model;

    public string Id => _model.Id;

    public string Title
    {
        get => _model.Title;
        set
        {
            if (_model.Title != value)
            {
                _model.Title = value;
                OnPropertyChanged();
            }
        }
    }

    public string RomPath
    {
        get => _model.RomPath;
        set
        {
            if (_model.RomPath != value)
            {
                _model.RomPath = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(HasRomFile));
            }
        }
    }

    public string ConsoleName
    {
        get => _model.ConsoleName;
        set
        {
            if (_model.ConsoleName != value)
            {
                _model.ConsoleName = value;
                OnPropertyChanged();
            }
        }
    }

    public SystemType SystemType
    {
        get => _model.SystemType;
        set
        {
            if (_model.SystemType != value)
            {
                _model.SystemType = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(SystemBadgeText));
                OnPropertyChanged(nameof(SystemBadgeColor));
            }
        }
    }

    public string SystemBadgeText => SystemType switch
    {
        SystemType.Genesis => "GENESIS",
        SystemType.SegaCD => "SEGA CD",
        SystemType.Sega32X => "32X",
        SystemType.MasterSystem => "MASTER SYS",
        SystemType.GameGear => "GAME GEAR",
        _ => "UNKNOWN"
    };

    public string SystemBadgeColor => SystemType switch
    {
        SystemType.SegaCD => "#1976D2", // Blue
        SystemType.Sega32X => "#D32F2F", // Red
        SystemType.MasterSystem => "#7B1FA2", // Purple
        SystemType.GameGear => "#F57C00", // Orange
        SystemType.Genesis => "#212121", // Dark Grey
        _ => "#757575"
    };

    public string ReleaseYear
    {
        get => _model.ReleaseYear;
        set
        {
            if (_model.ReleaseYear != value)
            {
                _model.ReleaseYear = value;
                OnPropertyChanged();
            }
        }
    }

    public string Developer
    {
        get => _model.Developer;
        set
        {
            if (_model.Developer != value)
            {
                _model.Developer = value;
                OnPropertyChanged();
            }
        }
    }

    public string Summary
    {
        get => _model.Summary;
        set
        {
            if (_model.Summary != value)
            {
                _model.Summary = value;
                OnPropertyChanged();
            }
        }
    }

    public string ArtworkPath
    {
        get => _model.ArtworkPath;
        set
        {
            if (_model.ArtworkPath != value)
            {
                _model.ArtworkPath = value;
                _model.CoverImagePath = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(CoverImagePath));
                OnPropertyChanged(nameof(HasCoverImage));
            }
        }
    }

    public string CoverImagePath
    {
        get => _model.CoverImagePath;
        set
        {
            if (_model.CoverImagePath != value)
            {
                _model.CoverImagePath = value;
                _model.ArtworkPath = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(ArtworkPath));
                OnPropertyChanged(nameof(HasCoverImage));
            }
        }
    }

    public bool HasRomFile => !string.IsNullOrWhiteSpace(RomPath) && File.Exists(RomPath);

    public bool HasCoverImage => !string.IsNullOrWhiteSpace(CoverImagePath) && File.Exists(CoverImagePath);

    public ICommand LaunchCommand { get; }
    public ICommand RenameCommand { get; }
    public ICommand ShowAboutCommand { get; }
    public ICommand DeleteCommand { get; }
    public ICommand ChangeCoverCommand { get; }
    public ICommand RemoveCoverCommand { get; }
    public ICommand RescrapeCommand { get; }

    public GameItemViewModel(
        GameItem model,
        Action<GameItemViewModel> onLaunch,
        Action<GameItemViewModel> onRename,
        Action<GameItemViewModel> onShowAbout,
        Action<GameItemViewModel>? onDelete = null,
        Action<GameItemViewModel>? onChangeCover = null,
        Action<GameItemViewModel>? onRemoveCover = null,
        Action<GameItemViewModel>? onRescrape = null)
    {
        _model = model ?? throw new ArgumentNullException(nameof(model));
        _onLaunch = onLaunch;
        _onRename = onRename;
        _onShowAbout = onShowAbout;
        _onDelete = onDelete;
        _onChangeCover = onChangeCover;
        _onRemoveCover = onRemoveCover;
        _onRescrape = onRescrape;

        LaunchCommand = new RelayCommand(_ => _onLaunch?.Invoke(this));
        RenameCommand = new RelayCommand(_ => _onRename?.Invoke(this));
        ShowAboutCommand = new RelayCommand(_ => _onShowAbout?.Invoke(this));
        DeleteCommand = new RelayCommand(_ => _onDelete?.Invoke(this));
        ChangeCoverCommand = new RelayCommand(_ => _onChangeCover?.Invoke(this));
        RemoveCoverCommand = new RelayCommand(_ => _onRemoveCover?.Invoke(this));
        RescrapeCommand = new RelayCommand(_ => _onRescrape?.Invoke(this));
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
