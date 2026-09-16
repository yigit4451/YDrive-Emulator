using System.Windows;

namespace SegaEmulator.Views;

public partial class RenameGameDialog : Window
{
    public string NewTitle { get; private set; } = string.Empty;

    public RenameGameDialog(string currentTitle)
    {
        InitializeComponent();
        TitleTextBox.Text = currentTitle;
        TitleTextBox.Focus();
        TitleTextBox.SelectAll();
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(TitleTextBox.Text))
        {
            MessageBox.Show((string)Application.Current.Resources["Msg_InvalidGameName"], (string)Application.Current.Resources["Msg_WarningTitle"], MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        NewTitle = TitleTextBox.Text.Trim();
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
