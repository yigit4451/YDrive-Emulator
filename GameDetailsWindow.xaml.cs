using System;
using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using SegaEmulator.Models;
using SegaEmulator.Services;
using SegaEmulator.ViewModels;
using System.ComponentModel;

namespace SegaEmulator.Views;

public partial class GameDetailsWindow : Window
{
    private readonly GameItemViewModel? _gameViewModel;
    private readonly GameItem? _gameModel;

    public GameDetailsWindow(GameItemViewModel gameViewModel)
    {
        InitializeComponent();
        _gameViewModel = gameViewModel;
        _gameModel = gameViewModel.Model;
        this.DataContext = _gameViewModel;

        Loaded += (s, e) => LoadCoverImage(_gameViewModel.CoverImagePath);
        _gameViewModel.PropertyChanged += GameViewModel_PropertyChanged;
        Unloaded += (s, e) => _gameViewModel.PropertyChanged -= GameViewModel_PropertyChanged;
    }

    private void GameViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(GameItemViewModel.CoverImagePath))
        {
            LoadCoverImage(_gameViewModel?.CoverImagePath);
        }
    }

    public GameDetailsWindow(GameItem game)
    {
        InitializeComponent();
        _gameModel = game;
        this.DataContext = _gameModel;

        Loaded += (s, e) => LoadCoverImage(game.CoverImagePath);
    }

    private void LoadCoverImage(string? coverImagePath)
    {
        try
        {
            if (!string.IsNullOrEmpty(coverImagePath) && File.Exists(coverImagePath))
            {
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.UriSource = new Uri(coverImagePath, UriKind.RelativeOrAbsolute);
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.CreateOptions = BitmapCreateOptions.IgnoreImageCache;
                bitmap.EndInit();
                bitmap.Freeze();

                CoverImage.Source = bitmap;
                CoverImage.Visibility = Visibility.Visible;
                PlaceholderBorder.Visibility = Visibility.Collapsed;
                RemoveCoverButton.Visibility = Visibility.Visible;
            }
            else
            {
                SetDefaultPlaceholder();
            }
        }
        catch (UnauthorizedAccessException uex)
        {
            System.Diagnostics.Debug.WriteLine($"[Görsel Erişim Izni Hatası] {uex.Message}");
            DiagnosticLog.WriteError("GameDetailsWindow", $"Görsel erişim hatası: {uex.Message}");
            SetDefaultPlaceholder();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Görsel Hatası] {ex.Message}");
            DiagnosticLog.WriteError("GameDetailsWindow", $"Görsel yükleme hatası: {ex.Message}");
            SetDefaultPlaceholder();
        }
    }

    private void SetDefaultPlaceholder()
    {
        CoverImage.Source = null;
        CoverImage.Visibility = Visibility.Collapsed;
        PlaceholderBorder.Visibility = Visibility.Visible;
        RemoveCoverButton.Visibility = Visibility.Collapsed;
    }

    private void ChangeCover_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dialog = new OpenFileDialog
            {
                Title = (string)Application.Current.Resources["Msg_SelectCover"],
                Filter = "Resim Dosyaları|*.png;*.jpg;*.jpeg;*.bmp;*.webp|Tüm Dosyalar|*.*",
                CheckFileExists = true
            };

            if (dialog.ShowDialog() == true)
            {
                string gameId = _gameViewModel?.Id ?? _gameModel?.Id ?? Guid.NewGuid().ToString();
                var service = new GameMetadataService();
                string savedPath = service.SaveCustomCoverImage(dialog.FileName, gameId);

                if (!string.IsNullOrEmpty(savedPath))
                {
                    if (_gameViewModel != null)
                    {
                        _gameViewModel.CoverImagePath = savedPath;
                        _gameViewModel.ArtworkPath = savedPath;
                    }
                    else if (_gameModel != null)
                    {
                        _gameModel.CoverImagePath = savedPath;
                        _gameModel.ArtworkPath = savedPath;
                    }

                    // Doğrudan BitmapImage yükleyip CoverImage.Source bileşenine atıyoruz
                    LoadCoverImage(savedPath);

                    if (Owner?.DataContext is MainViewModel mainVm)
                    {
                        mainVm.SaveLibrary();
                    }
                }
            }
        }
        catch (UnauthorizedAccessException uex)
        {
            System.Diagnostics.Debug.WriteLine($"[Kapak Resmini Değiştir Erişim Hatası] {uex.Message}");
            DiagnosticLog.WriteError("GameDetailsWindow", $"Kapak değiştir erişim engeli: {uex.Message}");
            string msg = (string)Application.Current.Resources["Msg_CoverError"];
            string title = (string)Application.Current.Resources["Msg_CoverErrorTitle"];
            MessageBox.Show(msg, title, MessageBoxButton.OK, MessageBoxImage.Warning);
            SetDefaultPlaceholder();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Kapak Resmini Değiştir Hatası] {ex.Message}");
            DiagnosticLog.WriteError("GameDetailsWindow", $"Kapak değiştir hatası: {ex.Message}");
            SetDefaultPlaceholder();
        }
    }

    private void RemoveCover_Click(object sender, RoutedEventArgs e)
    {
        string msg = (string)Application.Current.Resources["Msg_RemoveCoverConfirmSimple"];
        string title = (string)Application.Current.Resources["Msg_RemoveCoverTitle"];
        var confirm = MessageBox.Show(msg, title, MessageBoxButton.YesNo, MessageBoxImage.Question);

        if (confirm == MessageBoxResult.Yes)
        {
            if (_gameViewModel != null)
            {
                _gameViewModel.CoverImagePath = string.Empty;
                _gameViewModel.ArtworkPath = string.Empty;
            }
            else if (_gameModel != null)
            {
                _gameModel.CoverImagePath = string.Empty;
                _gameModel.ArtworkPath = string.Empty;
            }

            LoadCoverImage(null);

            if (Owner?.DataContext is MainViewModel mainVm)
            {
                mainVm.SaveLibrary();
            }
        }
    }

    private void Launch_Click(object sender, RoutedEventArgs e)
    {
        Close();
        if (_gameViewModel != null)
        {
            if (Owner?.DataContext is MainViewModel mainVm)
            {
                mainVm.LaunchGame(_gameViewModel);
            }
            else
            {
                _gameViewModel.LaunchCommand?.Execute(null);
            }
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
