using System;
using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Data.Converters;
using Avalonia.Input;
using Avalonia.VisualTree;
using YDrive.Core;
using YDrive.Services;
using YDrive.ViewModels;

namespace YDrive.ViewModels
{
    public class TopBarIconConverter : IValueConverter
    {
        public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            if (value is bool isVisible && isVisible)
                return "▲";
            return "▼";
        }

        public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => null;
    }

    public class PauseIconConverter : IValueConverter
    {
        public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            if (value is bool isPaused && isPaused)
                return "▶";
            return "⏸";
        }

        public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => null;
    }

    public class EditModeToTextConverter : IValueConverter
    {
        public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            if (value is bool isEditMode && isEditMode)
                return "✅ Kaydet & Çık";
            return "🎛 Kontrolleri Düzenle";
        }

        public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => null;
    }

    public class PauseModeToTextConverter : IValueConverter
    {
        public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            if (value is bool isPaused && isPaused)
                return "▶ Oyuna Devam Et";
            return "⏸ Duraklat";
        }

        public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => null;
    }
}

namespace YDrive.Views
{
    public partial class GameWindowView : UserControl
    {
        private Control? _draggedControl;
        private Point _dragOffset;

        public GameWindowView()
        {
            InitializeComponent();
        }

        private async void Control_OnLoaded(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
        {
            this.Focus();
            if (DataContext is GameWindowViewModel vm)
            {
                await vm.StartEmulationAsync();
            }
        }

        protected override void OnDataContextChanged(EventArgs e)
        {
            base.OnDataContextChanged(e);
            if (DataContext is GameWindowViewModel vm)
            {
                vm.OnFrameAvailable -= HandleFrameAvailable;
                vm.OnFrameAvailable += HandleFrameAvailable;

                vm.OnOverlayOpened -= HandleOverlayOpened;
                vm.OnOverlayOpened += HandleOverlayOpened;

                vm.OnOverlayClosed -= HandleOverlayClosed;
                vm.OnOverlayClosed += HandleOverlayClosed;

                vm.PropertyChanged -= Vm_PropertyChanged;
                vm.PropertyChanged += Vm_PropertyChanged;
            }
        }

        private void Vm_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(GameWindowViewModel.IsSaveLoadModalOpen))
            {
                if (DataContext is GameWindowViewModel vm && vm.IsSaveLoadModalOpen)
                {
                    Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                    {
                        var backBtn = this.FindControl<Button>("SaveModalBackButton");
                        backBtn?.Focus();
                    }, Avalonia.Threading.DispatcherPriority.Background);
                }
                else
                {
                    Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                    {
                        if (DataContext is GameWindowViewModel vm && vm.IsTopBarVisible)
                        {
                            var topBtn = this.FindControl<Button>("OverlayFirstButton");
                            topBtn?.Focus();
                        }
                        else
                        {
                            this.Focus();
                        }
                    }, Avalonia.Threading.DispatcherPriority.Background);
                }
            }
        }

        private void HandleOverlayOpened()
        {
            var topBtn = this.FindControl<Button>("OverlayFirstButton");
            topBtn?.Focus();
        }

        private void HandleOverlayClosed()
        {
            this.Focus();
        }

        private void HandleFrameAvailable()
        {
            ScreenImage?.InvalidateVisual();
        }

        protected override void OnAttachedToVisualTree(VisualTreeAttachmentEventArgs e)
        {
            base.OnAttachedToVisualTree(e);
            if (DataContext is GameWindowViewModel vm)
            {
                var topLevel = TopLevel.GetTopLevel(this);
                if (topLevel != null && topLevel.ClientSize.Width > 100 && topLevel.ClientSize.Height > 100)
                {
                    vm.InitializeButtonPositions(topLevel.ClientSize.Width, topLevel.ClientSize.Height);
                }
            }
        }

        protected override void OnSizeChanged(SizeChangedEventArgs e)
        {
            base.OnSizeChanged(e);
            if (DataContext is GameWindowViewModel vm && e.NewSize.Width > 100 && e.NewSize.Height > 100)
            {
                vm.InitializeButtonPositions(e.NewSize.Width, e.NewSize.Height);
            }
        }

        private void OnTouchCanvasSizeChanged(object? sender, SizeChangedEventArgs e)
        {
            if (DataContext is not GameWindowViewModel vm) return;
            if (e.NewSize.Width > 100 && e.NewSize.Height > 100)
            {
                vm.InitializeButtonPositions(e.NewSize.Width, e.NewSize.Height);
            }
        }

        protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
        {
            base.OnPropertyChanged(change);
            if (change.Property == DataContextProperty && change.NewValue is GameWindowViewModel vm)
            {
                var topLevel = TopLevel.GetTopLevel(this);
                if (topLevel != null && topLevel.ClientSize.Width > 100 && topLevel.ClientSize.Height > 100)
                {
                    vm.InitializeButtonPositions(topLevel.ClientSize.Width, topLevel.ClientSize.Height);
                }
                else if (this.Bounds.Width > 100 && this.Bounds.Height > 100)
                {
                    vm.InitializeButtonPositions(this.Bounds.Width, this.Bounds.Height);
                }
            }
        }

        private void OnCanvasPointerPressed(object? sender, PointerPressedEventArgs e)
        {
            if (DataContext is not GameWindowViewModel vm) return;
            if (sender is not Canvas canvas) return;

            var control = FindTouchControl(e.Source as Visual, canvas);
            if (control == null || control.Tag is not string tag) return;

            if (vm.IsEditMode)
            {
                _draggedControl = control;
                var canvasPos = e.GetPosition(canvas);
                
                double curLeft = Canvas.GetLeft(control);
                if (double.IsNaN(curLeft)) curLeft = 0;
                
                double curTop = Canvas.GetTop(control);
                if (double.IsNaN(curTop)) curTop = 0;

                _dragOffset = new Point(canvasPos.X - curLeft, canvasPos.Y - curTop);
                e.Pointer.Capture(canvas);
                e.Handled = true;
            }
            else
            {
                // Active Gameplay
                if (tag == "DPad")
                {
                    ProcessDPadTouch(control, e.GetPosition(control), vm);
                    e.Pointer.Capture(canvas);
                }
                else
                {
                    var btn = MapTagToJoypadButton(tag);
                    if (btn.HasValue)
                    {
                        vm.SetButtonState(btn.Value, true);
                    }
                }
                e.Handled = true;
            }
        }

        private void OnCanvasPointerMoved(object? sender, PointerEventArgs e)
        {
            if (DataContext is not GameWindowViewModel vm) return;
            if (sender is not Canvas canvas) return;

            if (vm.IsEditMode && _draggedControl != null && _draggedControl.Tag is string tag)
            {
                double ctrlW = !double.IsNaN(_draggedControl.Width) && _draggedControl.Width > 0 ? _draggedControl.Width : _draggedControl.Bounds.Width;
                double ctrlH = !double.IsNaN(_draggedControl.Height) && _draggedControl.Height > 0 ? _draggedControl.Height : _draggedControl.Bounds.Height;
                if (ctrlW <= 0) ctrlW = 60;
                if (ctrlH <= 0) ctrlH = 60;

                double canvasW = canvas.Bounds.Width > 100 ? canvas.Bounds.Width : 2400;
                double canvasH = canvas.Bounds.Height > 100 ? canvas.Bounds.Height : 1080;

                var canvasPos = e.GetPosition(canvas);
                double maxW = Math.Max(0, canvasW - ctrlW);
                double maxH = Math.Max(0, canvasH - ctrlH);
                double newLeft = Math.Clamp(canvasPos.X - _dragOffset.X, 0, maxW);
                double newTop = Math.Clamp(canvasPos.Y - _dragOffset.Y, 0, maxH);

                Canvas.SetLeft(_draggedControl, newLeft);
                Canvas.SetTop(_draggedControl, newTop);

                SettingsManager.Instance.Current.IsCustomPositioned = true;

                switch (tag)
                {
                    case "DPad":  vm.TouchDPadX = newLeft; vm.TouchDPadY = newTop; break;
                    case "A":     vm.TouchAX = newLeft; vm.TouchAY = newTop; break;
                    case "B":     vm.TouchBX = newLeft; vm.TouchBY = newTop; break;
                    case "C":     vm.TouchCX = newLeft; vm.TouchCY = newTop; break;
                    case "X":     vm.TouchXX = newLeft; vm.TouchXY = newTop; break;
                    case "Y":     vm.TouchYX = newLeft; vm.TouchYY = newTop; break;
                    case "Z":     vm.TouchZX = newLeft; vm.TouchZY = newTop; break;
                    case "Start": vm.TouchStartX = newLeft; vm.TouchStartY = newTop; break;
                }
                e.Handled = true;
            }
            else if (!vm.IsEditMode)
            {
                var control = FindTouchControl(e.Source as Visual, canvas);
                if (control != null && control.Tag is "DPad")
                {
                    ProcessDPadTouch(control, e.GetPosition(control), vm);
                    e.Handled = true;
                }
            }
        }

        private void OnCanvasPointerReleased(object? sender, PointerReleasedEventArgs e)
        {
            if (DataContext is not GameWindowViewModel vm) return;
            if (sender is not Canvas canvas) return;

            if (vm.IsEditMode)
            {
                if (_draggedControl != null)
                {
                    e.Pointer.Capture(null);
                    _draggedControl = null;
                    e.Handled = true;
                }
            }
            else
            {
                var control = FindTouchControl(e.Source as Visual, canvas);
                if (control != null && control.Tag is string tag)
                {
                    if (tag == "DPad")
                    {
                        vm.SetButtonState(RetroJoypadButton.Up, false);
                        vm.SetButtonState(RetroJoypadButton.Down, false);
                        vm.SetButtonState(RetroJoypadButton.Left, false);
                        vm.SetButtonState(RetroJoypadButton.Right, false);
                    }
                    else
                    {
                        var btn = MapTagToJoypadButton(tag);
                        if (btn.HasValue)
                        {
                            vm.SetButtonState(btn.Value, false);
                        }
                    }
                }
                else
                {
                    vm.ClearButtonStates();
                }
                e.Pointer.Capture(null);
                e.Handled = true;
            }
        }

        private Control? FindTouchControl(Visual? visual, Canvas canvas)
        {
            while (visual != null && visual != canvas)
            {
                if (visual is Control ctrl && ctrl.Tag is string tag && !string.IsNullOrEmpty(tag))
                {
                    return ctrl;
                }
                visual = visual.GetVisualParent();
            }
            return null;
        }

        private void ProcessDPadTouch(Control dpad, Point pos, GameWindowViewModel vm)
        {
            double cx = dpad.Bounds.Width > 0 ? dpad.Bounds.Width / 2 : 70;
            double cy = dpad.Bounds.Height > 0 ? dpad.Bounds.Height / 2 : 70;

            double dx = pos.X - cx;
            double dy = pos.Y - cy;
            double deadZone = 14;

            vm.SetButtonState(RetroJoypadButton.Up, dy < -deadZone);
            vm.SetButtonState(RetroJoypadButton.Down, dy > deadZone);
            vm.SetButtonState(RetroJoypadButton.Left, dx < -deadZone);
            vm.SetButtonState(RetroJoypadButton.Right, dx > deadZone);
        }

        private RetroJoypadButton? MapTagToJoypadButton(string tag)
        {
            return tag switch
            {
                "A" => RetroJoypadButton.Y,      // SEGA A
                "B" => RetroJoypadButton.B,      // SEGA B
                "C" => RetroJoypadButton.A,      // SEGA C
                "X" => RetroJoypadButton.L,      // SEGA X
                "Y" => RetroJoypadButton.X,      // SEGA Y
                "Z" => RetroJoypadButton.R,      // SEGA Z
                "Start" => RetroJoypadButton.Start,
                _ => null
            };
        }
    }
}
