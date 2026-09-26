class APNativeSmokeCommandlet extends Commandlet;

event int Main(string Parms)
{
    local APNativeClient Client;
    local float X, Y;
    Client = new class'APNativeClient';
    if (Client.GetVersion() != "UT99APNative 0.4.6") return 1;
    Client.DrawPickupMarker(None, vect(0,0,0), vect(1,1,1), class'Canvas'.default.DrawColor, false, false);
    if (Client.ProjectPoint(None, vect(0,0,0), X, Y)) return 1;
    Log("AP NATIVE LOAD PASS: " $ Client.GetVersion());
    return 0;
}

defaultproperties
{
    IsClient=False
    IsServer=False
    IsEditor=True
    LogToStdout=True
}
