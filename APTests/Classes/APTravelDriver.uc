class APTravelDriver extends Info config(UT99APTravelTest);

var config int VisitCount;
var APMutator AP;
var bool bFirstCheckSent;
var bool bSecondCheckSent;
var float Age;

function FailTest(string Reason)
{
    Log("AP TRAVEL FAIL: " $ Reason);
    ConsoleCommand("exit");
}

function Tick(float Delta)
{
    Age += Delta;
    if (Age > 25) { FailTest("timeout on visit " $ VisitCount); return; }
    if (AP == None) AP = APTravelGame(Level.Game).AP;
    if (AP == None || !AP.bReady) return;
    if (VisitCount == 0)
    {
        if (!bFirstCheckSent) { bFirstCheckSent = true; AP.Check(1); return; }
        if (!AP.IsUnlocked(1) || AP.Progress.IsPendingCheck(1)) return;
        VisitCount = 1;
        SaveConfig();
        Level.ServerTravel("?Restart", false);
    }
    else if (VisitCount == 1)
    {
        if (!AP.Progress.IsChecked(1) || !AP.IsUnlocked(1) || AP.Client.ItemIndex != 4 ||
            AP.Progress.PendingWeaponAmmo[5] != 1)
        { FailTest("server state not restored after travel"); return; }
        if (!bSecondCheckSent) { bSecondCheckSent = true; AP.Check(2); return; }
        if (AP.Progress.IsPendingCheck(2)) return;
        VisitCount = 2;
        SaveConfig();
        Log("AP TRAVEL PASS");
        ConsoleCommand("exit");
    }
}

defaultproperties
{
    bAlwaysTick=True
}
