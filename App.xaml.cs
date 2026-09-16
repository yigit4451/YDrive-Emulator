using System;
using System.Globalization;
using System.Windows;
using System.Windows.Threading;

namespace SegaEmulator;

public partial class App : Application
{
    public App()
    {
        DispatcherUnhandledException += App_DispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += CurrentDomain_UnhandledException;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var dict = new ResourceDictionary();
        
        string lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
        if (lang == "tr")
        {
            dict.Source = new Uri("pack://application:,,,/Resources/Strings.tr.xaml");
        }
        else
        {
            dict.Source = new Uri("pack://application:,,,/Resources/Strings.en.xaml");
        }
        
        Application.Current.Resources.MergedDictionaries.Add(dict);
    }

    private void App_DispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        DiagnosticLog.WriteError("App", $"Unhandled Dispatcher Exception: {e.Exception}");
        string msg = string.Format((string)Application.Current.Resources["Msg_AppError"], e.Exception.Message, e.Exception.ToString());
        string title = (string)Application.Current.Resources["Msg_AppErrorTitle"];
        MessageBox.Show(msg, title, MessageBoxButton.OK, MessageBoxImage.Error);
        e.Handled = true;
    }

    private void CurrentDomain_UnhandledException(object sender, UnhandledExceptionEventArgs e)
    {
        if (e.ExceptionObject is Exception ex)
        {
            DiagnosticLog.WriteError("App", $"Unhandled Domain Exception: {ex}");
            string msg = string.Format((string)Application.Current.Resources["Msg_AppCriticalError"], ex.Message, ex.ToString());
            string title = (string)Application.Current.Resources["Msg_AppCriticalErrorTitle"];
            MessageBox.Show(msg, title, MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        DiagnosticLog.WriteSessionSummary($"Exit Code: {e.ApplicationExitCode}");
        DiagnosticLog.FlushAndClose();
        base.OnExit(e);
    }
}
