using System;
using Avalonia;

namespace YDrive.Desktop;

sealed class Program
{
    public static void Main(string[] args)
    {
        YDrive.App.PlatformService = new DesktopPlatformService();
        BuildAvaloniaApp()
            .StartWithClassicDesktopLifetime(args);
    }

    // Avalonia configuration, don't remove; also used by visual designer.
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
