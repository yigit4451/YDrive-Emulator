using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

class Program
{
    static void Main()
    {
        string input = @"src\YDrive\Assets\blue_hedgehog.ico";
        string output = @"YDrive.CrossPlatform\YDrive.iOS\Resources\Assets.xcassets\AppIcon.appiconset\icon_1024x1024.png";
        
        Directory.CreateDirectory(Path.GetDirectoryName(output));
        
        using (Icon icon = new Icon(input))
        {
            using (Bitmap bitmap = icon.ToBitmap())
            {
                bitmap.Save(output, ImageFormat.Png);
            }
        }
        Console.WriteLine("Done.");
    }
}
