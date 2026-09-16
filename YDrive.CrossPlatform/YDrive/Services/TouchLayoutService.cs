using System;
using YDrive.Models;

namespace YDrive.Services;

public record struct TouchCoordinates(
    double DPadX, double DPadY,
    double AX, double AY,
    double BX, double BY,
    double CX, double CY,
    double XX, double XY,
    double YX, double YY,
    double ZX, double ZY,
    double StartX, double StartY
);

public static class TouchLayoutService
{
    public const int CurrentLayoutVersion = 8;

    // Fixed Button Dimensions (px)
    public const double DPadSize = 160.0;
    public const double StartWidth = 80.0;
    public const double StartHeight = 40.0;
    public const double BtnAbcSize = 68.0;
    public const double BtnXyzSize = 52.0;

    /// <summary>
    /// Computes default Sega Genesis 6-Button layout coordinates based on screen dimensions.
    /// Grounded ergonomically near the bottom edge with clean non-overlapping thumb arc.
    /// </summary>
    public static TouchCoordinates CalculateDefaultCoordinates(double screenWidth, double screenHeight)
    {
        // Prevent layout collapse from intermediate or invalid sizing passes
        if (screenWidth < 600 || screenHeight < 300)
        {
            screenWidth = 1280;
            screenHeight = 720;
        }
        
        double w = screenWidth;
        double h = screenHeight;

        // Tablet/Telefon Ekran Boyutu Faktörü
        double scaleFactor = Math.Clamp(w / 1280.0, 1.0, 1.2);
        
        // Önceki "çok güzel olan" orijinal piksel değerlerine birebir sadık kaldık
        // A, B, C arası boşluk tam 75, alt ve üst satır arası tam 70 piksel olacak.
        double spacingX = 75 * scaleFactor;
        double spacingY = 70 * scaleFactor;

        // Sol Kenar: D-Pad
        double dpadX = Math.Max(20, 36 * scaleFactor);
        double dpadY = h - (200 * scaleFactor);

        // Alt Merkez: START
        double startX = (w / 2.0) - 35;
        double startY = h - 65;

        // Sağ Kenar: 6'lı Buton Grubu (C Butonuna Kilitli - Orijinal hiza: w-110, h-160)
        double cx = w - (110 * scaleFactor);
        double cy = h - (160 * scaleFactor);

        // Alt sıra (A, B, C) - Orijinal hiza: C(w-110, h-160), B(w-185, h-145), A(w-260, h-130)
        double bx = cx - spacingX;
        double by = cy + (15 * scaleFactor);
        
        double ax = bx - spacingX;
        double ay = by + (15 * scaleFactor);

        // Üst sıra (X, Y, Z) - Orijinal hiza: Z(w-100, h-230), Y(w-175, h-215), X(w-250, h-200)
        // Yani alt sıraya göre sağa 10px kayık ve spacingY (70) kadar yukarıda
        double zx = cx + (10 * scaleFactor);
        double zy = cy - spacingY;
        
        double yx = bx + (10 * scaleFactor);
        double yy = by - spacingY;
        
        double xx = ax + (10 * scaleFactor);
        double xy = ay - spacingY;

        // Güvenlik Sınırlandırması (Clamping):
        // Önizleme ekranı dar olsa bile A butonunun D-Pad ile çakışmaması için
        // Tüm kümeyi birlikte kaydırıyoruz ki şekil bozulmasın
        double minAx = dpadX + 140;
        if (ax < minAx)
        {
            double pushDiff = minAx - ax;
            ax += pushDiff;
            bx += pushDiff;
            cx += pushDiff;
            
            xx += pushDiff;
            yx += pushDiff;
            zx += pushDiff;
        }

        return new TouchCoordinates(
            dpadX, dpadY,
            ax, ay,
            bx, by,
            cx, cy,
            xx, xy,
            yx, yy,
            zx, zy,
            startX, startY
        );
    }
}
