using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using SegaEmulator.ViewModels;

namespace SegaEmulator.Views;

public partial class SettingsWindow : Window
{
    private BindingItem? _activeBindingItem;

    public SettingsWindow()
    {
        InitializeComponent();
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        var vm = DataContext as SettingsViewModel;
        if (vm != null && vm.HasChanges() && !vm.IsSaved)
        {
            var result = MessageBox.Show(
                (string)Application.Current.Resources["Msg_UnsavedChanges"],
                (string)Application.Current.Resources["Msg_WarningTitle"],
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
                
            if (result != MessageBoxResult.Yes)
            {
                e.Cancel = true;
            }
            else
            {
                vm.RestoreBiosFiles();
            }
        }
        else if (vm != null && !vm.IsSaved)
        {
            vm.RestoreBiosFiles();
        }
        base.OnClosing(e);
    }

    private void AssignButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button button && button.Tag is BindingItem item)
        {
            _activeBindingItem = item;
            button.Content = Application.Current.Resources["Msg_PressKey"];
            this.Focus();
        }
    }

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (_activeBindingItem != null)
        {
            e.Handled = true; // Prevent other handlers from triggering
            
            // Catch actual key, not system keys
            Key key = e.Key == Key.System ? e.SystemKey : e.Key;
            
            // If escape, cancel mapping
            if (key != Key.Escape)
            {
                _activeBindingItem.BoundKey = key;
            }

            _activeBindingItem = null;
            
            // Force re-binding to update button text
            var vm = DataContext as SettingsViewModel;
            if (vm != null)
            {
                var view1 = System.Windows.Data.CollectionViewSource.GetDefaultView(vm.ControlsVM.Player1Bindings);
                view1.Refresh();
                var view2 = System.Windows.Data.CollectionViewSource.GetDefaultView(vm.ControlsVM.Player2Bindings);
                view2.Refresh();
            }
        }
    }
}
