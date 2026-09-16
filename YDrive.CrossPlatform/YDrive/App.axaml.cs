using System;
using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using YDrive.ViewModels;
using YDrive.Views;

namespace YDrive;

public partial class App : Application
{
    public static YDrive.Services.IPlatformService PlatformService { get; set; } = null!;

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        try
        {
            if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
            {
                desktop.MainWindow = new MainWindow
                {
                    DataContext = new MainViewModel(PlatformService)
                };
            }
            else if (ApplicationLifetime is ISingleViewApplicationLifetime singleViewPlatform)
            {
                singleViewPlatform.MainView = new MainView
                {
                    DataContext = new MainViewModel(PlatformService)
                };
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[App] Startup error: {ex}");
            Console.Error.WriteLine($"[App] Startup error: {ex}");

            if (ApplicationLifetime is ISingleViewApplicationLifetime fallback)
            {
                fallback.MainView = new ContentControl
                {
                    Content = new TextBlock
                    {
                        Text = $"YDrive Startup Error:\n\n{ex.Message}\n\n{ex.StackTrace}",
                        Foreground = Avalonia.Media.Brushes.White,
                        Margin = new Thickness(24),
                        TextWrapping = Avalonia.Media.TextWrapping.Wrap
                    }
                };
            }
        }

        base.OnFrameworkInitializationCompleted();
    }
}
