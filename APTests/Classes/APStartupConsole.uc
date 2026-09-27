// Test real menu and practice-game startup without an AP server connection
class APStartupConsole extends UTConsole;

var bool bChecked;

event Tick(float Delta)
{
    local APMenuWindow W;
    local APMenuClient Menu;
    local APMutator AP;
    local APNativeClient Bridge;
    Super.Tick(Delta);
    if (bChecked || Viewport == None || Viewport.Actor == None) return;
    bChecked = true;
    class'APConsoleTextArea'.static.Install(Viewport.Actor);
    LaunchUWindow();
    W = APMenuWindow(Root.CreateWindow(class'APMenuWindow', 70, 15, 500, 450));
    Menu = APMenuClient(W.ClientArea);
    AP = Menu.AP;
    if (AP == None || AP.Progress == None || AP.bReady || AP.Client != None)
    { Log("AP STARTUP FAIL: offline mutator initialization"); ConsoleCommand("exit"); return; }
    Menu.Tick(0);
    if (!Menu.PlayButton.bDisabled)
    { Log("AP STARTUP FAIL: offline play enabled"); ConsoleCommand("exit"); return; }
    Bridge = new class'APNativeClient';
    if (Bridge.GetVersion() != "UT99APNative 0.4.6")
    { Log("AP STARTUP FAIL: native binding"); ConsoleCommand("exit"); return; }
    Log("AP STARTUP PASS: " $ Viewport.Actor.Level.Game.Class);
    ConsoleCommand("exit");
}

