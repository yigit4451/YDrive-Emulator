using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

class Program
{
    static void Main()
    {
        string path = @"..\YDrive.CrossPlatform\YDrive.Android\lib\arm64-v8a\libgenesis_plus_gx_libretro_android.so";
        if (!File.Exists(path)) { Console.WriteLine("File not found at " + Path.GetFullPath(path)); return; }

        byte[] bytes = File.ReadAllBytes(path);
        
        // Strip nulls to make regex easier on raw bytes
        string text = Encoding.ASCII.GetString(bytes).Replace("\0", " ");

        Console.WriteLine("Searching for CHD strings...");
        if (text.Contains("libchdr")) Console.WriteLine("FOUND: libchdr");
        if (text.Contains("chd_open")) Console.WriteLine("FOUND: chd_open");
        if (text.Contains("chd")) Console.WriteLine("FOUND: chd");
        
        var match = Regex.Match(text, @"mdx?\s*\|\s*smd");
        if (match.Success) 
        {
            // Just find the block around it
            int start = Math.Max(0, match.Index - 20);
            Console.WriteLine($"Extensions: {text.Substring(start, 100)}");
        }
        else
        {
            Console.WriteLine("Could not find valid_extensions string.");
        }
    }
}
