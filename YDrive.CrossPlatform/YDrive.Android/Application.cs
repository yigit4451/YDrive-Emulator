using System;
using Android.App;
using Android.Runtime;

namespace YDrive.Android;

[Application]
public class Application : global::Android.App.Application
{
    public Application(IntPtr handle, JniHandleOwnership transfer)
        : base(handle, transfer)
    {
    }

    public override void OnCreate()
    {
        base.OnCreate();

        AndroidEnvironment.UnhandledExceptionRaiser += (sender, args) =>
        {
            global::Android.Util.Log.Error("YDrive", $"[CRASH] Unhandled: {args.Exception}");
        };

        AppDomain.CurrentDomain.UnhandledException += (sender, args) =>
        {
            global::Android.Util.Log.Error("YDrive", $"[CRASH] AppDomain: {args.ExceptionObject}");
        };
    }
}
