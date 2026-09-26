class APProbeDriver extends Info;

var float Age, CheckedAt;
var bool bSent;

function Tick(float Delta)
{
    local APMutator AP;
    local PlayerPawn Human;
    local Bot Enemy;
    local NavigationPoint Start;
    local APPickupMarker Marker;
    local int I;
    Age += Delta;
    if (Age > 25) { Log("AP REAL SERVER FAIL: timeout"); ConsoleCommand("exit"); return; }
    AP = APProbeGame(Level.Game).AP;
    if (AP == None || !AP.bReady) return;
    if (!bSent)
    {
        for (Marker = AP.FirstPickup; Marker != None; Marker = Marker.NextPickup)
            if (AP.PickupUnlocked(Marker.PickupIndex)) break;
        if (AP.bPickupLocations && (Marker == None || Marker.ItemFlags < 0)) return;
        if (!AP.IsStage()) { Log("AP REAL SERVER FAIL: starting map locked"); ConsoleCommand("exit"); return; }
        if (!AP.SendServerCommand("!help"))
        { Log("AP REAL SERVER FAIL: sending !help"); ConsoleCommand("exit"); return; }
        Start = Level.Game.FindPlayerStart(None);
        Human = Spawn(class'TMale1',,,Start.Location);
        Start = Level.Game.FindPlayerStart(None);
        Enemy = Spawn(class'TMale2Bot',,,Start.Location);
        if (Human == None || Enemy == None)
        { Log("AP REAL SERVER FAIL: spawn"); ConsoleCommand("exit"); return; }
        Human.PlayerReplicationInfo.bIsSpectator = false;
        if (AP.bPickupLocations)
        {
            Human.bCollideWorld = false;
            Human.SetCollision(false, false, false);
            Human.SetLocation(Marker.Location);
            Marker.Touch(Human);
            if (!AP.Progress.IsChecked(5000 + Marker.PickupIndex))
            { Log("AP REAL SERVER FAIL: no pickup check"); ConsoleCommand("exit"); return; }
            Log("AP REAL PICKUP " $ Marker.PickupIndex $ " FLAGS " $ Marker.ItemFlags);
        }
        for (I = 0; I < AP.FragIncrement; I++) AP.ScoreKill(Human, Enemy);
        if (!AP.Progress.IsChecked(AP.CurrentMap * 10 + 1))
        { Log("AP REAL SERVER FAIL: no frag check"); ConsoleCommand("exit"); return; }
        bSent = true;
        CheckedAt = Age;
    }
    else if (Age - CheckedAt > 2)
    {
        Log("AP REAL SERVER PASS");
        ConsoleCommand("exit");
    }
}
