using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.VisualTree;
using YDrive.Services;
using YDrive.ViewModels;

namespace YDrive.Views;

public partial class SettingsView : UserControl
{
    private Control? _hudDraggedControl;
    private Point _hudDragOffset;

    public SettingsView()
    {
        InitializeComponent();
    }

    protected override void OnAttachedToVisualTree(VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        if (DataContext is SettingsViewModel vm)
        {
            var topLevel = TopLevel.GetTopLevel(this);
            if (topLevel != null && topLevel.ClientSize.Width > 100 && topLevel.ClientSize.Height > 100)
            {
                vm.ScreenWidth = topLevel.ClientSize.Width;
                vm.ScreenHeight = topLevel.ClientSize.Height;
                if (!SettingsManager.Instance.Current.IsCustomPositioned)
                {
                    vm.AutoFitToScreen(topLevel.ClientSize.Width, topLevel.ClientSize.Height);
                }
                else
                {
                    vm.ClampToScreen(topLevel.ClientSize.Width, topLevel.ClientSize.Height);
                }
            }
            
            // Subscribe to PropertyChanged to manually update visuals when binding fails
            vm.PropertyChanged += Vm_PropertyChanged;
        }
    }

    protected override void OnDetachedFromVisualTree(VisualTreeAttachmentEventArgs e)
    {
        base.OnDetachedFromVisualTree(e);
        if (DataContext is SettingsViewModel vm)
        {
            vm.PropertyChanged -= Vm_PropertyChanged;
        }
    }

    private void Vm_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (sender is not SettingsViewModel vm) return;
        
        var canvas = this.FindControl<Canvas>("HudCanvas");
        if (canvas == null) return;
        
        if (e.PropertyName == nameof(vm.SelectedControlScale) || e.PropertyName == nameof(vm.SelectedControlOpacity))
        {
            foreach (var child in canvas.Children)
            {
                if (child is Control ctrl && ctrl.Tag is string tag && tag == vm.SelectedControlName)
                {
                    if (e.PropertyName == nameof(vm.SelectedControlScale))
                    {
                        ctrl.RenderTransform = new Avalonia.Media.ScaleTransform(vm.SelectedControlScale, vm.SelectedControlScale);
                    }
                    if (e.PropertyName == nameof(vm.SelectedControlOpacity))
                    {
                        ctrl.Opacity = vm.SelectedControlOpacity;
                    }
                }
            }
        }
        else if (e.PropertyName != null && (e.PropertyName.EndsWith("Scale") || e.PropertyName.EndsWith("Opacity")))
        {
            // Fallback for when "Sıfırla" (Reset) is pressed and individual properties are updated.
            string prop = e.PropertyName;
            string targetTag = "";
            bool isScale = prop.EndsWith("Scale");
            if (prop.StartsWith("Touch") && prop.Length > 10)
            {
                targetTag = prop.Substring(5, prop.Length - 5 - (isScale ? 5 : 7)); // e.g. TouchDPadScale -> DPad
            }
            if (!string.IsNullOrEmpty(targetTag))
            {
                foreach (var child in canvas.Children)
                {
                    if (child is Control ctrl && ctrl.Tag is string tag && tag == targetTag)
                    {
                        var propInfo = vm.GetType().GetProperty(prop);
                        if (propInfo != null)
                        {
                            double val = (double)propInfo.GetValue(vm)!;
                            if (isScale)
                            {
                                ctrl.RenderTransform = new Avalonia.Media.ScaleTransform(val, val);
                            }
                            else
                            {
                                ctrl.Opacity = val;
                            }
                        }
                    }
                }
            }
        }
    }

    protected override void OnSizeChanged(SizeChangedEventArgs e)
    {
        base.OnSizeChanged(e);
        if (DataContext is SettingsViewModel vm && e.NewSize.Width > 100 && e.NewSize.Height > 100)
        {
            vm.ScreenWidth = e.NewSize.Width;
            vm.ScreenHeight = e.NewSize.Height;
            if (!SettingsManager.Instance.Current.IsCustomPositioned)
            {
                vm.AutoFitToScreen(e.NewSize.Width, e.NewSize.Height);
            }
            else
            {
                vm.ClampToScreen(e.NewSize.Width, e.NewSize.Height);
            }
        }
    }

    private void OnHudCanvasSizeChanged(object? sender, SizeChangedEventArgs e)
    {
        if (DataContext is not SettingsViewModel vm) return;
        if (e.NewSize.Width > 100 && e.NewSize.Height > 100)
        {
            vm.ScreenWidth = e.NewSize.Width;
            vm.ScreenHeight = e.NewSize.Height;
            if (!SettingsManager.Instance.Current.IsCustomPositioned)
            {
                vm.AutoFitToScreen(e.NewSize.Width, e.NewSize.Height);
            }
            else
            {
                vm.ClampToScreen(e.NewSize.Width, e.NewSize.Height);
            }
        }
    }

    private void OnHudCanvasPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (DataContext is not SettingsViewModel vm || !vm.IsHudEditorOpen) return;
        if (sender is not Canvas canvas) return;



        var control = FindHudTouchControl(e.Source as Visual, canvas);
        if (control == null || control.Tag is not string tag)
        {
            vm.IsControlSelected = false;
            return;
        }

        vm.IsControlSelected = true;
        vm.SelectedControlName = tag;

        _hudDraggedControl = control;
        var canvasPos = e.GetPosition(canvas);
        
        double curLeft = Canvas.GetLeft(control);
        if (double.IsNaN(curLeft)) curLeft = 0;
        
        double curTop = Canvas.GetTop(control);
        if (double.IsNaN(curTop)) curTop = 0;

        _hudDragOffset = new Point(canvasPos.X - curLeft, canvasPos.Y - curTop);
        e.Pointer.Capture(canvas);
        e.Handled = true;
    }

    private void OnHudCanvasPointerMoved(object? sender, PointerEventArgs e)
    {
        if (DataContext is not SettingsViewModel vm || !vm.IsHudEditorOpen) return;
        if (_hudDraggedControl == null || sender is not Canvas canvas) return;

        var canvasPos = e.GetPosition(canvas);
        double ctrlW = !double.IsNaN(_hudDraggedControl.Width) && _hudDraggedControl.Width > 0 ? _hudDraggedControl.Width : _hudDraggedControl.Bounds.Width;
        double ctrlH = !double.IsNaN(_hudDraggedControl.Height) && _hudDraggedControl.Height > 0 ? _hudDraggedControl.Height : _hudDraggedControl.Bounds.Height;
        if (ctrlW <= 0) ctrlW = 60;
        if (ctrlH <= 0) ctrlH = 60;

        double canvasW = canvas.Bounds.Width > 100 ? canvas.Bounds.Width : (vm.ScreenWidth > 100 ? vm.ScreenWidth : 2400);
        double canvasH = canvas.Bounds.Height > 100 ? canvas.Bounds.Height : (vm.ScreenHeight > 100 ? vm.ScreenHeight : 1080);

        double maxW = Math.Max(0, canvasW - ctrlW);
        double maxH = Math.Max(0, canvasH - ctrlH);
        double newLeft = Math.Clamp(canvasPos.X - _hudDragOffset.X, 0, maxW);
        double newTop = Math.Clamp(canvasPos.Y - _hudDragOffset.Y, 0, maxH);

        // Do not use Canvas.SetLeft or Canvas.SetTop here!
        // It overrides the XAML bindings (Local Value > Binding).
        // The bindings to vm.TouchDPadX etc. will automatically update the UI.
        SettingsManager.Instance.Current.IsCustomPositioned = true;

        if (_hudDraggedControl.Tag is string tag)
        {
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
            if (vm.SelectedControlName == tag)
            {
                vm.SelectionBoxX = newLeft;
                vm.SelectionBoxY = newTop;
            }
        }
        e.Handled = true;
    }

    private void OnHudCanvasPointerReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (_hudDraggedControl != null)
        {
            e.Pointer.Capture(null);
            _hudDraggedControl = null;
            e.Handled = true;
        }
    }

    private Control? FindHudTouchControl(Visual? visual, Canvas canvas)
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
}
