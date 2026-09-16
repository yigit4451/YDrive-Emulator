using System;
using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using YDrive.Models;
using Avalonia.Input;
using YDrive.Core;

namespace YDrive.ViewModels;

public partial class BindingItem : ObservableObject
{
    [ObservableProperty]
    private RetroJoypadButton _button;
    
    [ObservableProperty]
    private string _displayName = string.Empty;
    
    [ObservableProperty]
    private Key _boundKey;
    
    [ObservableProperty]
    private bool _isEditing;
}

public partial class ControlsViewModel : ViewModelBase
{
    [ObservableProperty]
    private int _selectedTabIndex;

    [ObservableProperty]
    private bool _isPlayer2Enabled;

    partial void OnIsPlayer2EnabledChanged(bool value)
    {
        if (!value && SelectedTabIndex == 1)
        {
            // If P2 is turned off while selected, jump back to P1 tab
            SelectedTabIndex = 0;
        }
    }

    public ObservableCollection<BindingItem> Player1Bindings { get; } = new();
    public ObservableCollection<BindingItem> Player2Bindings { get; } = new();

    public ControlsViewModel()
    {
        // Add default bindings for Player 1
        Player1Bindings.Add(new BindingItem { Button = RetroJoypadButton.Up, DisplayName = "Up", BoundKey = Key.Up });
        Player1Bindings.Add(new BindingItem { Button = RetroJoypadButton.Down, DisplayName = "Down", BoundKey = Key.Down });
        Player1Bindings.Add(new BindingItem { Button = RetroJoypadButton.A, DisplayName = "Button A", BoundKey = Key.A });
        
        // Settings bindings would normally load from SettingsManager
    }
}
