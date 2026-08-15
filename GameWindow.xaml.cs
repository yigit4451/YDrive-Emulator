using System;
using System.Windows;
using System.Windows.Input;
using SegaEmulator.ViewModels;

namespace SegaEmulator.Views
{
    public partial class GameWindow : Window
    {
        private FullscreenWindow? _fullscreenWindow;

        public GameWindow()
        {
            InitializeComponent();

            PreviewKeyDown += GameWindow_PreviewKeyDown;
            PreviewKeyUp += GameWindow_PreviewKeyUp;
            DataContextChanged += GameWindow_DataContextChanged;
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hwnd, int index);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hwnd, int index, int value);

        private const int GWL_STYLE = -16;
        private const int WS_MAXIMIZEBOX = 0x10000;
        private const int WS_MINIMIZEBOX = 0x20000;

        private void RemoveMinMaxButtons()
        {
            var hwnd = new System.Windows.Interop.WindowInteropHelper(this).Handle;
            if (hwnd != IntPtr.Zero)
            {
                var currentStyle = GetWindowLong(hwnd, GWL_STYLE);
                SetWindowLong(hwnd, GWL_STYLE, currentStyle & ~WS_MAXIMIZEBOX & ~WS_MINIMIZEBOX);
            }
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            RemoveMinMaxButtons();
        }

        private void GameWindow_DataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
        {
            if (e.OldValue is GameWindowViewModel oldVm)
            {
                oldVm.PropertyChanged -= Vm_PropertyChanged;
            }
            if (e.NewValue is GameWindowViewModel newVm)
            {
                newVm.PropertyChanged += Vm_PropertyChanged;
            }
        }

        private void Vm_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(GameWindowViewModel.IsFullscreen))
            {
                var vm = DataContext as GameWindowViewModel;
                if (vm != null && vm.IsFullscreen)
                {
                    if (_fullscreenWindow == null)
                    {
                        _fullscreenWindow = new FullscreenWindow();
                        _fullscreenWindow.DataContext = vm;
                    }
                    _fullscreenWindow.Show();
                    this.Hide();
                }
                else
                {
                    if (_fullscreenWindow != null)
                    {
                        _fullscreenWindow.Close();
                        _fullscreenWindow = null;
                    }
                    this.Show();
                    RemoveMinMaxButtons();
                }
            }
        }

        private void GameWindow_PreviewKeyDown(object sender, KeyEventArgs e)
        {
            if (e.IsRepeat) return;

            var vm = DataContext as GameWindowViewModel;
            if (vm == null) return;

            if (e.Key == Key.F11)
            {
                vm.ToggleFullscreenCommand.Execute(null);
                e.Handled = true;
                return;
            }

            if (e.Key == Key.Escape)
            {
                if (vm.IsFullscreen)
                {
                    vm.ToggleFullscreenCommand.Execute(null);
                    e.Handled = true;
                    return;
                }
            }

            if (vm.IsRunning)
            {
                vm.Input.KeyDown(e.Key);
            }
        }

        private void GameWindow_PreviewKeyUp(object sender, KeyEventArgs e)
        {
            if (DataContext is GameWindowViewModel vm && vm.IsRunning)
            {
                vm.Input.KeyUp(e.Key);
            }
        }

        protected override void OnClosed(EventArgs e)
        {
            base.OnClosed(e);

            if (DataContext is IDisposable disposable)
            {
                disposable.Dispose();
            }
        }
    }
}
