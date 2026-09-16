using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using YDrive.ViewModels;

namespace YDrive.Views;

public partial class SettingsWindow : Window
{
    private SettingsViewModel? _vm;

    public SettingsWindow()
    {
        InitializeComponent();
    }

    protected override void OnDataContextChanged(System.EventArgs e)
    {
        base.OnDataContextChanged(e);
        _vm = DataContext as SettingsViewModel;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (_vm?.IsAwaitingKey == true)
        {
            e.Handled = true;
            _vm.OnKeyPressed(e.Key.ToString());
        }
    }
}
