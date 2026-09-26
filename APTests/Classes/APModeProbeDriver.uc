class APModeProbeDriver extends Info;

function PostBeginPlay()
{
    SetTimer(0.5, false);
}

function Timer()
{
    local APMutator AP;
    local TeamGamePlus Game;
    local TMale1 Human;
    local TMale1Bot Enemy;
    local PlayerStart Start, EnemyStart;
    local CTFFlag Flag;
    local FortStandard Fort;
    local int MapIndex, PickupIndex, Milestone, Count, InLogic, Total, I;

    Game = TeamGamePlus(Level.Game);
    foreach AllActors(class'APMutator', AP) break;
    if (AP == None || Game == None || AP.CurrentMap < 37)
    { Log("AP MODE FAIL: map setup"); ConsoleCommand("exit"); return; }
    MapIndex = AP.CurrentMap;
    AP.bAutoConnect = false;
    AP.Progress.SelectSlot("AP mode probe " $ MapIndex);
    AP.SetSelected(MapIndex, true);
    AP.SetUnlocked(MapIndex, true);
    AP.WeaponLogicPercentage = 0;
    AP.GoalRequired = 1;
    AP.bReady = true;
    AP.PickupUnlockMode = 1;
    AP.Client = Spawn(class'APClient');
    AP.Client.AP = AP;
    AP.Client.Bridge = new class'APNativeClient';
    AP.Client.bFailed = true;
    foreach AllActors(class'PlayerStart', Start) break;
    if (Start != None) Human = Spawn(class'TMale1',,, Start.Location + vect(0,0,32));
    if (Human == None || Human.PlayerReplicationInfo == None)
    { Log("AP MODE FAIL: human setup pawn=" $ Human $ " pri=" $ Human.PlayerReplicationInfo);
      ConsoleCommand("exit"); return; }
    Human.PlayerReplicationInfo.Team = 0;
    Human.PlayerReplicationInfo.bIsSpectator = false;
    foreach AllActors(class'PlayerStart', EnemyStart)
        if (EnemyStart != Start) break;
    if (EnemyStart != None) Enemy = Spawn(class'TMale1Bot',,, EnemyStart.Location + vect(0,0,32));
    if (Enemy != None && Enemy.PlayerReplicationInfo == None)
        Enemy.PlayerReplicationInfo = Spawn(class'PlayerReplicationInfo');
    if (Enemy == None || Enemy.PlayerReplicationInfo == None)
    { Log("AP MODE FAIL: enemy setup"); ConsoleCommand("exit"); return; }
    Enemy.bIsPlayer = true;
    AP.FragIncrement = 1;
    AP.MatchFragLimit = 2;
    Game.Teams[0].Score = 0;
    for (PickupIndex = 0; PickupIndex < class'APCatalog'.default.PickupCount; PickupIndex++)
        if (class'APCatalog'.static.PickupMap(PickupIndex) == MapIndex) break;
    if (PickupIndex >= class'APCatalog'.default.PickupCount || !AP.AddPickupLocation(PickupIndex))
    { Log("AP MODE FAIL: pickup catalog"); ConsoleCommand("exit"); return; }
    AP.bPickupLocations = true;
    AP.InitPickupMarkers();
    if (AP.FirstPickup == None || !AP.IsStage())
    { Log("AP MODE FAIL: marker or stage"); ConsoleCommand("exit"); return; }
    AP.GetCheckCounts(Count, InLogic, Total);
    if (Total != 4 + class'APCatalog'.default.MapObjectiveCount[MapIndex] ||
        InLogic != Total - 1)
    { Log("AP MODE FAIL: location counts " $ Count $ "/" $ InLogic $ "/" $ Total); ConsoleCommand("exit"); return; }
    Enemy.PlayerReplicationInfo.Team = 0;
    AP.ScoreKill(Human, Enemy);
    if (AP.Progress.GetFrag(MapIndex) != 0)
    { Log("AP MODE FAIL: friendly kill counted"); ConsoleCommand("exit"); return; }
    Enemy.PlayerReplicationInfo.Team = 1;
    AP.ScoreKill(Human, Enemy);
    AP.ScoreKill(Human, Enemy);
    AP.ScoreKill(Human, Enemy);
    if (AP.Progress.GetFrag(MapIndex) != 2 ||
        !AP.Progress.IsChecked(AP.TeamFragIndex(MapIndex, 1)) ||
        !AP.Progress.IsChecked(AP.TeamFragIndex(MapIndex, 2)) ||
        AP.DecodeCheck(AP.TeamFragIndex(MapIndex, 3), MapIndex, Milestone) ||
        AP.CompletionName(AP.TeamFragIndex(MapIndex, 1), true) !=
            (class'APCatalog'.default.Maps[MapIndex] $ " - Frag Milestone 1"))
    { Log("AP MODE FAIL: enemy frag checks"); ConsoleCommand("exit"); return; }
    if (class'APCatalog'.default.MapMode[MapIndex] == 1)
    {
        foreach AllActors(class'CTFFlag', Flag)
            if (Flag.Team != 0) break;
        if (Flag == None || Flag.Team == 0)
        { Log("AP MODE FAIL: enemy flag"); ConsoleCommand("exit"); return; }
        for (I = 0; I < 3; I++) APCTF(Game).ScoreFlag(Human, Flag);
    }
    else if (class'APCatalog'.default.MapMode[MapIndex] == 2)
    { Game.Teams[0].Score = 100; APDomination(Game).Timer(); }
    else
    {
        APAssault(Game).Attacker = Game.Teams[0];
        APAssault(Game).Defender = Game.Teams[1];
        Count = 0;
        foreach AllActors(class'FortStandard', Fort)
            if (AP.AssaultObjectiveIndex(Fort) >= 0) Count++;
        if (Count != class'APCatalog'.default.MapObjectiveCount[MapIndex])
        { Log("AP MODE FAIL: assault markers " $ Count); ConsoleCommand("exit"); return; }
        foreach AllActors(class'FortStandard', Fort)
            if (Fort.Name == 'FortStandard0') break;
        if (Fort == None || Fort.Name != 'FortStandard0')
        { Log("AP MODE FAIL: assault fort"); ConsoleCommand("exit"); return; }
        APAssault(Game).RemoveFort(Fort, Human);
        if (AP.AssaultObjectiveIndex(Fort) >= 0)
        { Log("AP MODE FAIL: completed objective marked"); ConsoleCommand("exit"); return; }
        if (!APAssault(Game).bAssaultWon)
            foreach AllActors(class'FortStandard', Fort)
                if (Fort.Name != 'FortStandard0' && !APAssault(Game).bAssaultWon)
                    APAssault(Game).RemoveFort(Fort, Human);
    }
    if (!AP.Progress.IsChecked(AP.CheckIndex(MapIndex, 1)))
    { Log("AP MODE FAIL: objective check ended=" $ Game.bGameEnded $ " stage=" $ AP.IsStage()
        $ " score=" $ Game.Teams[0].Score); ConsoleCommand("exit"); return; }
    if (class'APCatalog'.default.MapMode[MapIndex] != 3 &&
        !AP.Progress.IsChecked(AP.CheckIndex(MapIndex, class'APCatalog'.default.MapObjectiveCount[MapIndex])))
    { Log("AP MODE FAIL: final objective check"); ConsoleCommand("exit"); return; }
    Game.bGameEnded = true;
    AP.Timer();
    if (!AP.Progress.IsChecked(AP.CheckIndex(MapIndex, 0)) || AP.WinCount() != 1)
    { Log("AP MODE FAIL: win check"); ConsoleCommand("exit"); return; }
    if (!AP.DecodeCheck(AP.CheckIndex(MapIndex, 1), MapIndex, Milestone) || Milestone != 1)
    { Log("AP MODE FAIL: check decode"); ConsoleCommand("exit"); return; }
    Log("AP MODE PASS: " $ Level.Outer.Name);
    ConsoleCommand("exit");
}
