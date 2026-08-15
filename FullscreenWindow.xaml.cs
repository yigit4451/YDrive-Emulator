using System;
using System.Windows;
using System.Windows.Input;
using SegaEmulator.ViewModels;

namespace SegaEmulator.Views
{
    public partial class FullscreenWindow : Window
    {
        public FullscreenWindow()
        {
            InitializeComponent();
            
            PreviewKeyDown += FullscreenWindow_PreviewKeyDown;
            PreviewKeyUp += FullscreenWindow_PreviewKeyUp;
        }

        private void FullscreenWindow_PreviewKeyDown(object sender, KeyEventArgs e)
        {
            if (e.IsRepeat) return;

            var vm = DataContext as GameWindowViewModel;
            if (vm == null) return;

            if (e.Key == Key.F11 || e.Key == Key.Escape)
            {
                vm.ToggleFullscreenCommand.Execute(null);
                e.Handled = true;
                return;
            }

            if (vm.IsRunning)
            {
                vm.Input.KeyDown(e.Key);
            }
        }

        private void FullscreenWindow_PreviewKeyUp(object sender, KeyEventArgs e)
        {
            if (DataContext is GameWindowViewModel vm && vm.IsRunning)
            {
                vm.Input.KeyUp(e.Key);
            }
        }

        protected override void OnClosed(EventArgs e)
        {
            base.OnClosed(e);

            var vm = DataContext as GameWindowViewModel;
            if (vm != null && vm.IsFullscreen)
            {
                // If the user forcibly closed this window (e.g. Alt+F4),
                // we should exit fullscreen mode on the viewmodel.
                vm.ToggleFullscreenCommand.Execute(null);
            }
        }
    }
}
