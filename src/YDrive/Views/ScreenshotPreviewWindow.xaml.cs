using System;
using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;

namespace SegaEmulator.Views
{
    public partial class ScreenshotPreviewWindow : Window
    {
        private BitmapSource _screenshot;
        private string _savePath;

        public bool WasSaved { get; private set; } = false;

        public ScreenshotPreviewWindow(BitmapSource screenshot, string defaultSavePath)
        {
            InitializeComponent();
            
            _screenshot = screenshot;
            _savePath = defaultSavePath;

            PreviewImage.Source = _screenshot;
            PathTextBox.Text = _savePath;
        }

        private void ChangeBtn_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new Microsoft.Win32.SaveFileDialog
            {
                Title = "Kaydedilecek Konumu Seçin", // Optional: use a resource if we want it localized perfectly
                Filter = "PNG Image|*.png",
                FileName = Path.GetFileName(_savePath),
                InitialDirectory = Path.GetDirectoryName(_savePath)
            };

            if (dialog.ShowDialog() == true)
            {
                _savePath = dialog.FileName;
                PathTextBox.Text = _savePath;
            }
        }

        private void SaveBtn_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                // Ensure directory exists
                string? dir = Path.GetDirectoryName(_savePath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                // Save as PNG
                using (var fileStream = new FileStream(_savePath, FileMode.Create))
                {
                    BitmapEncoder encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(BitmapFrame.Create(_screenshot));
                    encoder.Save(fileStream);
                }
                
                WasSaved = true;
                this.DialogResult = true;
                this.Close();
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to save screenshot: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void CancelBtn_Click(object sender, RoutedEventArgs e)
        {
            this.DialogResult = false;
            this.Close();
        }
    }
}
