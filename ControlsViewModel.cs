using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using SegaEmulator.Core;
using SegaEmulator.Input;

namespace SegaEmulator.ViewModels;

public class ControlsViewModel : INotifyPropertyChanged
{
    private readonly SegaEmulator.Input.InputManager _inputManager;
    private Dictionary<Key, RetroJoypadButton> _p1Map;
    private Dictionary<Key, RetroJoypadButton> _p2Map;

    public ObservableCollection<BindingItem> Player1Bindings { get; } = new();
    public ObservableCollection<BindingItem> Player2Bindings { get; } = new();

    public ICommand SaveCommand { get; }
    public ICommand CancelCommand { get; }

    public ControlsViewModel(SegaEmulator.Input.InputManager inputManager, Action closeAction)
    {
        _inputManager = inputManager;
        
        _p1Map = _inputManager.GetKeyMap(0);
        _p2Map = _inputManager.GetKeyMap(1);

        LoadBindings(Player1Bindings, _p1Map);
        LoadBindings(Player2Bindings, _p2Map);

        SaveCommand = new RelayCommand(_ => 
        {
            SaveBindings(_p1Map, Player1Bindings);
            SaveBindings(_p2Map, Player2Bindings);
            _inputManager.SaveSettings(_p1Map, _p2Map);
            closeAction();
        });

        CancelCommand = new RelayCommand(_ => closeAction());
    }

    public void Save()
    {
        SaveBindings(_p1Map, Player1Bindings);
        SaveBindings(_p2Map, Player2Bindings);
        _inputManager.SaveSettings(_p1Map, _p2Map);
    }

    private void LoadBindings(ObservableCollection<BindingItem> collection, Dictionary<Key, RetroJoypadButton> map)
    {
        var reverseMap = map.GroupBy(x => x.Value).ToDictionary(g => g.Key, g => g.First().Key);
        
        var buttons = new[] 
        { 
            RetroJoypadButton.Up, RetroJoypadButton.Down, RetroJoypadButton.Left, RetroJoypadButton.Right,
            RetroJoypadButton.Y, RetroJoypadButton.B, RetroJoypadButton.A, // A, B, C
            RetroJoypadButton.L, RetroJoypadButton.X, RetroJoypadButton.R, // X, Y, Z
            RetroJoypadButton.Start, RetroJoypadButton.Select
        };

        foreach (var button in buttons)
        {
            reverseMap.TryGetValue(button, out Key key);
            
            // Map Libretro buttons to SEGA buttons for UI display
            string displayName = button switch
            {
                RetroJoypadButton.Y => "A Butonu",
                RetroJoypadButton.B => "B Butonu",
                RetroJoypadButton.A => "C Butonu",
                RetroJoypadButton.L => "X Butonu",
                RetroJoypadButton.X => "Y Butonu",
                RetroJoypadButton.R => "Z Butonu",
                RetroJoypadButton.Select => "Mode",
                _ => button.ToString()
            };

            collection.Add(new BindingItem { Button = button, DisplayName = displayName, BoundKey = key });
        }
    }

    private void SaveBindings(Dictionary<Key, RetroJoypadButton> map, ObservableCollection<BindingItem> collection)
    {
        map.Clear();
        foreach (var item in collection)
        {
            if (item.BoundKey != Key.None)
            {
                map[item.BoundKey] = item.Button;
            }
        }
    }

    public bool HasChanges()
    {
        if (HasBindingChanges(_p1Map, Player1Bindings)) return true;
        if (HasBindingChanges(_p2Map, Player2Bindings)) return true;
        return false;
    }

    private bool HasBindingChanges(Dictionary<Key, RetroJoypadButton> map, ObservableCollection<BindingItem> collection)
    {
        var reverseMap = map.GroupBy(x => x.Value).ToDictionary(g => g.Key, g => g.First().Key);
        
        foreach(var item in collection)
        {
            reverseMap.TryGetValue(item.Button, out Key expectedKey);
            if (item.BoundKey != expectedKey)
                return true;
        }
        return false;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}

public class BindingItem : INotifyPropertyChanged
{
    private Key _boundKey;
    
    public RetroJoypadButton Button { get; set; }
    public string DisplayName { get; set; } = "";
    
    public Key BoundKey
    {
        get => _boundKey;
        set
        {
            if (_boundKey != value)
            {
                _boundKey = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(BoundKey)));
            }
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}
