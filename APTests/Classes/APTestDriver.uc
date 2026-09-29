class APTestDriver extends Info;

var APMutator AP;
var PlayerPawn Human;
var Bot Enemy;
var int Phase;
var bool bReattached;
var float Elapsed;
var APPickupMarker TimerMarker;
var float TimerStarted;
var int ObservedItemIndex;
var bool bSawLiveItemBurst;

function FailTest(string Reason)
{
    Log("AP INTEGRATION FAIL: " $ Reason);
    ConsoleCommand("exit");
}

function bool CheckReplay()
{
    local APDeathMatch Game;
    Game = APDeathMatch(Level.Game);
    Game.EndTime = Level.TimeSeconds - Game.RestartWait - 1;
    Game.Timer();
    if (Level.NextURL != "") { FailTest("results restarted automatically"); return false; }
    Game.RestartGame();
    if (Level.NextURL != "?Restart" || Level.bNextItems)
    { FailTest("FIRE did not replay the same arena"); return false; }
    return true;
}

function Tick(float Delta)
{
    local int I, LastCheck, MapIndex, Milestone;
    local int Collected, InLogic, Total, ArenaChecks, SlotChecks, ExpectedItems;
    local byte Allowed;
    local Ammo SharedAmmo;
    local Weapon Gun;
    local Inventory SeenItem;
    local APPickupMarker Marker;
    local bool bSeenByBot;
    local bool bVariedSkill;
    local float EffectiveSkill;
    local BlockAll Blocker;
    local vector Orb;
    local color C;
    local string Completion;
    Elapsed += Delta;
    if (Elapsed > 45)
    {
        if (AP != None) Log("AP TEST STATUS: " $ AP.Status $ " ready=" $ AP.bReady);
        if (AP != None && AP.FirstPickup != None) Log("AP TEST FLAGS: " $ AP.FirstPickup.ItemFlags);
        FailTest("timeout, phase " $ Phase); return;
    }
    if (AP == None) { AP = APTestGame(Level.Game).AP; return; }
    if (AP.Client != None)
    {
        if (AP.Client.ItemIndex - ObservedItemIndex > 16)
        { FailTest("item burst processed in one frame"); return; }
        ObservedItemIndex = AP.Client.ItemIndex;
        if (Phase == 1 && AP.bReady && AP.Client.PendingItems != "")
            bSawLiveItemBurst = true;
    }
    if (!AP.bReady) return;
    if (Phase == 0 && AP.WeaponLogicPercentage > 0 && !bReattached)
    {
        bReattached = true;
        AP.Connect();
        return;
    }
    LastCheck = AP.CheckIndex(0, AP.MatchFragLimit / AP.FragIncrement);
    ArenaChecks = 1 + AP.MatchFragLimit / AP.FragIncrement;
    SlotChecks = 2 * ArenaChecks;
    ExpectedItems = 5 + APTestGame(Level.Game).TestItemBurst;
    if (AP.PickupUnlockMode == 1) ExpectedItems += 2;
    else if (AP.PickupUnlockMode == 2) ExpectedItems += 3;
    if (AP.bPickupLocations)
        for (I = 0; I < class'APCatalog'.default.PickupCount; I++)
            if (AP.DecodeCheck(5000 + I, MapIndex, Milestone))
            {
                SlotChecks++;
                if (MapIndex == 0) ArenaChecks++;
            }
    if (Phase == 0)
    {
        if (AP.bPickupLocations)
        {
            if (AP.FirstPickup == None) { FailTest("no pickup volumes"); return; }
            for (Marker = AP.FirstPickup; Marker != None; Marker = Marker.NextPickup)
                if (Marker.ItemFlags < 0) return;
        }
        if (DeathMatchPlus(Level.Game).BotConfig.Difficulty != AP.BotSkill ||
            DeathMatchPlus(Level.Game).RemainingBots + DeathMatchPlus(Level.Game).NumBots != AP.BotCount)
        { FailTest("configured bot count or skill"); return; }
        if (!AP.IsUnlocked(0) || !AP.Weapons[5].bSet || AP.IsUnlocked(1))
        { FailTest("initial inventory"); return; }
        if (AP.bDeathLink != (AP.WeaponLogicPercentage > 0))
        { FailTest("death link slot option"); return; }
        if (AP.WeaponLogicPercentage > 0)
        {
            if (AP.WeaponsOnMap(0) != 3 || AP.StageWeaponsNeeded(0) != 1 ||
                !AP.CanEnterMap(0) || !AP.IsStage())
            { FailTest("starting arena weapon logic"); return; }
            AP.Weapons[5].bSet = false;
            AP.GetCheckCounts(Collected, InLogic, Total);
            if (AP.CanEnterMap(0) || AP.IsStage() || AP.InLogicOnMap(0) != 0)
            { FailTest("missing weapon did not lock arena"); return; }
            AP.Weapons[5].bSet = true;
            if (!AP.CanEnterMap(0) || !AP.IsStage())
            { FailTest("weapon did not reopen arena"); return; }
        }
        if (AP.PickupUnlockMode == 1 &&
            (!AP.PickupFamilies[0].bSet || !AP.PickupFamilies[1].bSet))
        { FailTest("family unlock inventory"); return; }
        if (AP.PickupUnlockMode == 2 &&
            (!AP.PickupTypes[18].bSet || !AP.PickupTypes[19].bSet || !AP.PickupTypes[20].bSet))
        { FailTest("pickup-type unlock inventory"); return; }
        I = -1;
        if (AP.CompleteHint("!h", I) != "!help" ||
            AP.CompleteHint("!h", I) != "!hint" ||
            AP.CompleteHint("!h", I) != "!hint_location")
        { FailTest("server command completion cycle"); return; }
        I = -1;
        if (AP.CompleteHint("!rem", I) != "!remaining")
        { FailTest("server command completion"); return; }
        I = -1;
        if (AP.CompleteHint("!hint shock", I) != "!hint Shock Rifle Unlock")
        { FailTest("item completion"); return; }
        I = -1;
        if (AP.CompleteHint("!hint health ref", I) != "!hint Health Refill")
        { FailTest("filler item completion"); return; }
        I = -1;
        if (AP.CompleteHint("!hint Ammo Refill", I) != "!hint Ammo Refill" ||
            AP.CompleteHint("!hint Nothing", I) != "!hint Nothing")
        { FailTest("removed filler completion"); return; }
        if (AP.PickupUnlockMode == 2)
        {
            I = -1;
            if (AP.CompleteHint("!hint Med Box Pickup", I) != "!hint Med Box Pickup Unlock")
            { FailTest("pickup-type completion"); return; }
        }
        I = -1;
        if (AP.CompleteHint("!hint dm-", I) != "!hint DM-Oblivion Unlock" ||
            AP.CompleteHint("!hint dm-", I) != "!hint DM-Stalwart Unlock" ||
            AP.CompleteHint("!hint dm-", I) != "!hint DM-Oblivion Unlock")
        { FailTest("completion cycle/selected maps"); return; }
        I = -1;
        if (AP.CompleteHint("!hint_location Oblivion - Win", I) != "!hint_location DM-Oblivion - Win")
        { FailTest("win completion"); return; }
        I = -1;
        if (AP.CompleteHint("!hint_location Oblivion - Frag Milestone 1", I) != "!hint_location DM-Oblivion - Frag Milestone 1")
        { FailTest("frag completion"); return; }
        I = -1;
        Completion = "!hint_location DM-Oblivion - Pickup " $ class'APCatalog'.static.PickupLabel(0);
        if (AP.bPickupLocations && AP.CompleteHint(Completion, I) != Completion)
        { FailTest("pickup completion"); return; }
        if (!AP.bPickupLocations && AP.CompletionName(5000, true) != "")
        { FailTest("pickup completion in legacy seed"); return; }
        if (AP.CompleteHint("!hint nonexistent", I) != "!hint nonexistent" ||
            AP.CompleteHint("stat fps", I) != "stat fps")
        { FailTest("unmatched completion changed input"); return; }
        I = -1;
        if (AP.CompleteMutate("mut", I) != "mutate ")
        { FailTest("mutate completion"); return; }
        I = -1;
        if (AP.CompleteMutate("mutate ap", I) != "mutate ap " ||
            AP.CompleteMutate("mutate ap", I) != "mutate ap allrespawns")
        { FailTest("AP command completion"); return; }
        I = -1;
        if (AP.CompleteMutate("mutate ap ", I) != "mutate ap allrespawns" ||
            AP.CompleteMutate("mutate ap ", I) != "mutate ap connect" ||
            AP.CompleteMutate("mutate ap ", I) != "mutate ap disconnect")
        { FailTest("AP command alphabetical order"); return; }
        I = -1;
        if (AP.CompleteMutate("mutate ap st", I) != "mutate ap start " ||
            AP.CompleteMutate("mutate ap st", I) != "mutate ap status" ||
            AP.CompleteMutate("mutate ap st", I) != "mutate ap start ")
        { FailTest("AP subcommand cycling"); return; }
        I = -1;
        if (AP.CompleteMutate("mutate ap start dm-o", I) != "mutate ap start DM-Oblivion" ||
            AP.CompleteMutate("mutate ap start dm-o", I) != "mutate ap start DM-Oblivion")
        { FailTest("start map completion"); return; }
        I = -1;
        if (AP.CompleteMutate("mutate ap z", I) != "mutate ap z" ||
            AP.CompleteMutate("stat fps", I) != "stat fps")
        { FailTest("unmatched mutate completion changed input"); return; }
        I = -1;
        if (AP.CompleteMutate("mutate ap sk", I) != "mutate ap skillspread" ||
            AP.CompleteMutate("mutate ap_sk", I) != "mutate ap_sk")
        { FailTest("skill spread completion"); return; }
        if (!AP.SendServerCommand("!help")) { FailTest("send AP command"); return; }
        AP.GetCheckCounts(Collected, InLogic, Total);
        if (Collected != 0 || InLogic != ArenaChecks || Total != SlotChecks ||
            AP.CollectedOnMap(0) != 0 || AP.TotalOnMap(0) != ArenaChecks ||
            AP.TotalOnMap(1) != SlotChecks - ArenaChecks)
        { FailTest("initial HUD counts"); return; }
        Human = Spawn(class'TMale1');
        Enemy = Spawn(class'TMale2Bot');
        if (Human == None || Enemy == None) { FailTest("spawn test pawns"); return; }
        AP.BotSkillSpread = 0;
        Enemy.InitializeSkill(3);
        APDeathMatch(Level.Game).ModifyBehaviour(Enemy);
        if (Enemy.Skill != 3 || !Enemy.bNovice)
        { FailTest("zero skill spread changed bot"); return; }
        AP.BotSkillSpread = 1;
        for (I = 0; I < 16; I++)
        {
            Enemy.InitializeSkill(3);
            APDeathMatch(Level.Game).ModifyBehaviour(Enemy);
            EffectiveSkill = Enemy.Skill;
            if (!Enemy.bNovice) EffectiveSkill += 4;
            if (EffectiveSkill < 2 || EffectiveSkill > 4)
            { FailTest("skill spread bounds"); return; }
            if (EffectiveSkill != 3) bVariedSkill = true;
        }
        if (!bVariedSkill) { FailTest("skill spread did not vary bots"); return; }
        AP.BotSkillSpread = 0;
        // Use engine PlayerReplicationInfo and real inventory/pickup hooks
        Human.PlayerReplicationInfo.bIsSpectator = false;
        DeathMatchPlus(Level.Game).bRequireReady = false;
        Level.Game.AddDefaultInventory(Human);
        if (Human.FindInventoryType(class'UT_FlakCannon') == None)
        { FailTest("grant unlocked weapon"); return; }
        Human.Health = 50;
        AP.Progress.PendingHealth = 1;
        AP.ApplyFiller();
        if (Human.Health != 51 || AP.Progress.PendingHealth != 0)
        { FailTest("health refill"); return; }
        AP.Progress.PendingArmor = 1;
        AP.ApplyFiller();
        SeenItem = Human.FindInventoryType(class'ThighPads');
        if (SeenItem == None || SeenItem.Charge != 1 || AP.Progress.PendingArmor != 0)
        { FailTest("armor refill"); return; }
        Gun = Weapon(Human.FindInventoryType(class'UT_FlakCannon'));
        Human.Weapon = Gun;
        Gun.AmmoType.AmmoAmount = 0;
        AP.Progress.PendingWeaponAmmo[5] = 1;
        AP.ApplyFiller();
        if (Gun.AmmoType.AmmoAmount != 2 || AP.Progress.PendingWeaponAmmo[5] != 0)
        { FailTest("Flak Cannon ammo filler"); return; }
        Gun.AmmoType.AmmoAmount = 0;
        SharedAmmo = Ammo(Human.FindInventoryType(class'MiniAmmo'));
        if (SharedAmmo == None || Human.FindInventoryType(class'Minigun2') != None)
        { FailTest("Enforcer ammo pool"); return; }
        SharedAmmo.AmmoAmount = 0;
        AP.Progress.PendingWeaponAmmo[4] = 1;
        AP.ApplyFiller();
        if (SharedAmmo.AmmoAmount != 10 || AP.Progress.PendingWeaponAmmo[4] != 0)
        { FailTest("shared bullet ammo filler"); return; }
        Gun = Spawn(class'ShockRifle');
        if (!AP.HandlePickupQuery(Human, Gun, Allowed) || Allowed != 0)
        { FailTest("locked weapon pickup"); return; }
        Gun.Destroy();
        if (AP.bPickupLocations)
        {
            Human.SetCollision(false, false, false);
            Human.bCollideWorld = false;
            for (Marker = AP.FirstPickup; Marker != None; Marker = Marker.NextPickup)
            {
                // Server flags: filler 0, useful 2, progression 1
                if (!(Marker.PickupIndex % 3 == 0 && Marker.ItemFlags == 0) &&
                    !(Marker.PickupIndex % 3 == 1 && Marker.ItemFlags == 2) &&
                    !(Marker.PickupIndex % 3 == 2 && Marker.ItemFlags == 1))
                { FailTest("wrong scout flags"); return; }
                Human.SetLocation(Marker.Location);
                Marker.Touch(Enemy);
                Human.Health = 0;
                Marker.Touch(Human);
                Human.Health = 100;
                Human.PlayerReplicationInfo.bIsSpectator = true;
                Marker.Touch(Human);
                Human.PlayerReplicationInfo.bIsSpectator = false;
                AP.bReady = false;
                Marker.Touch(Human);
                AP.bReady = true;
                if (AP.Progress.IsChecked(5000 + Marker.PickupIndex))
                { FailTest("invalid pickup collector"); return; }
                if (Marker.PickupIndex == 0)
                {
                    if (AP.PickupUnlockMode != 0)
                    {
                        if (AP.PickupUnlockMode == 1) AP.PickupFamilies[0].bSet = false;
                        else AP.PickupTypes[18].bSet = false;
                        Marker.UpdateFamilyVisibility();
                        if (Marker.Pickup.bHidden || Marker.Pickup.DrawType != DT_None ||
                            !Marker.Pickup.bCollideActors ||
                            AP.PickupUnlocked(0))
                        { FailTest("locked pickup not hidden"); return; }
                        bSeenByBot = false;
                        foreach VisibleCollidingActors(class'Inventory', SeenItem, 128,
                            Marker.Location + vect(0,0,64), true)
                            if (SeenItem == Marker.Pickup) { bSeenByBot = true; break; }
                        if (!bSeenByBot) { FailTest("bot cannot discover locked pickup"); return; }
                        Allowed = 1;
                        if (!AP.HandlePickupQuery(Human, Marker.Pickup, Allowed) || Allowed != 0)
                        { FailTest("locked pickup allowed"); return; }
                        AP.Check(5000);
                        if (AP.Progress.IsChecked(5000))
                        { FailTest("locked pickup check sent"); return; }
                        if (AP.PickupUnlockMode == 1) AP.PickupFamilies[0].bSet = true;
                        else AP.PickupTypes[18].bSet = true;
                        AP.InventoryReady();
                        if (Marker.Pickup.bHidden || Marker.Pickup.DrawType == DT_None ||
                            !Marker.Pickup.bCollideActors)
                        { FailTest("live unlock did not reveal available pickup"); return; }
                        if (AP.PickupUnlockMode == 1) AP.PickupFamilies[0].bSet = false;
                        else AP.PickupTypes[18].bSet = false;
                        Marker.UpdateFamilyVisibility();
                        Enemy.Health = 50;
                        if (Marker.Pickup.BotDesireability(Enemy) <= 0)
                        { FailTest("bot does not want locked pickup"); return; }
                        Marker.Pickup.Touch(Enemy);
                        if (!Marker.Pickup.IsInState('Sleeping') ||
                            AP.Progress.IsChecked(5000))
                        { FailTest("bot could not take locked pickup"); return; }
                        if (AP.PickupUnlockMode == 1) AP.PickupFamilies[0].bSet = true;
                        else AP.PickupTypes[18].bSet = true;
                        AP.InventoryReady();
                        if (!Marker.Pickup.IsInState('Sleeping') || !Marker.Pickup.bHidden ||
                            Marker.Pickup.DrawType == DT_None)
                        { FailTest("unlock skipped stock respawn timer"); return; }
                        Marker.Pickup.GotoState('Pickup');
                        if (Marker.Pickup.bHidden || Marker.Pickup.DrawType == DT_None ||
                            !Marker.Pickup.bCollideActors ||
                            !AP.PickupUnlocked(0) || !AP.PickupUnlocked(2))
                        { FailTest("pickup did not appear on respawn"); return; }
                    }
                    Orb = Marker.Location + vect(0,0,1) * (Marker.BoxExtent.Z + 12);
                    if (!Marker.OrbVisible(Human, Orb + vect(0,0,24)))
                    { FailTest("visible orb hidden"); return; }
                    Blocker = Spawn(class'APMarkerBlocker',,,Orb + vect(0,0,12));
                    if (Blocker == None) { FailTest("spawn trace blocker"); return; }
                    if (Marker.OrbVisible(Human, Orb + vect(0,0,24)))
                    { FailTest("orb visible through blocker"); return; }
                    Blocker.Destroy();
                    C = class'APPickupMarker'.static.ClassificationColor(3);
                    if (C.R != 175 || C.G != 153 || C.B != 239)
                    { FailTest("progression flag priority"); return; }
                    Enemy.Health = 50;
                    Marker.Pickup.Touch(Enemy);
                    if (!Marker.Pickup.IsInState('Sleeping') || !Marker.Pickup.bHidden)
                    { FailTest("bot did not consume health pickup"); return; }
                }
                else Marker.Pickup.GotoState('Sleeping');
                Marker.Touch(Human);
                AP.HandlePickupQuery(Human, Marker.Pickup, Allowed);
                if (AP.Progress.IsChecked(5000 + Marker.PickupIndex))
                { FailTest("unspawned pickup sent check"); return; }
                Marker.Pickup.GotoState('Pickup');
                if (Marker.PickupIndex == 0)
                {
                    Human.Health = 50;
                    // Pickup hides before the marker sees its touch
                    Marker.Pickup.Touch(Human);
                    if (!Marker.Pickup.bHidden || !AP.Progress.IsChecked(5000 + Marker.PickupIndex))
                    { FailTest("human pickup lost check before marker touch"); return; }
                    Human.Health = 100;
                }
                Marker.Touch(Human);
                Marker.Touch(Human);
                if (!AP.Progress.IsChecked(5000 + Marker.PickupIndex))
                { FailTest("pickup check not sent"); return; }
            }
        }
        AP.ScoreKill(Human, Human);
        AP.ScoreKill(Enemy, Human);
        AP.bReady = false;
        AP.ScoreKill(Human, Enemy);
        AP.bReady = true;
        if (AP.Progress.GetFrag(0) != 0 || AP.Progress.GetFrag(1) != 3)
        { FailTest("invalid kill or server frag synchronization"); return; }
        if (DeathMatchPlus(Level.Game).FragLimit != AP.MatchFragLimit)
        { FailTest("match target depends on check spacing"); return; }
        for (I = 1; I <= AP.MatchFragLimit; I++)
        {
            AP.ScoreKill(Human, Enemy);
            Milestone = I / AP.FragIncrement;
            if (Milestone > 0 && !AP.Progress.IsChecked(AP.CheckIndex(0, Milestone)))
            { FailTest("missing kill check"); return; }
            if (Milestone < 100 && AP.Progress.IsChecked(AP.CheckIndex(0, Milestone + 1)))
            { FailTest("premature kill check"); return; }
        }
        AP.ScoreKill(Human, Enemy);
        if (!AP.Progress.IsChecked(LastCheck) || AP.Progress.GetFrag(0) != AP.MatchFragLimit ||
            AP.Progress.GetFrag(1) != 3)
        { FailTest("kill cap or per-arena counter"); return; }
        if (AP.CheckIndex(36, 100) != 3736 || AP.CheckIndex(1, 0) != 101 ||
            AP.DecodeCheck(3737, MapIndex, Milestone) || AP.DecodeCheck(-1, MapIndex, Milestone))
        { FailTest("location ID bounds"); return; }
        // Test winner scan at end of round, including bot wins.
        Enemy.PlayerReplicationInfo.Score = 100;
        Human.PlayerReplicationInfo.Score = 0;
        Level.Game.bGameEnded = true;
        AP.Timer();
        if (AP.Progress.IsChecked(0)) { FailTest("bot win counted"); return; }
        AP.bHandledEnd = false;
        Human.PlayerReplicationInfo.Score = 101;
        AP.Timer();
        if (!AP.Progress.IsChecked(0) || AP.WinCount() != 1)
        { FailTest("human win not counted"); return; }
        AP.UpdateCheckSummary();
        Completion = "AP checks (DM-Oblivion): " $ ArenaChecks $ " / " $ ArenaChecks;
        if (AP.PickupUnlockMode != 0) Completion $= " (" $ ArenaChecks $ ")";
        if (AP.CheckSummary != Completion)
        { FailTest("completed arena HUD counts"); return; }
        Phase = 1;
        Log("AP TEST: awaiting reconnect and map unlock");
    }
    else if (Phase == 1 && AP.IsUnlocked(1))
    {
        if (APTestGame(Level.Game).TestItemBurst > 0 && !bSawLiveItemBurst)
        { FailTest("live item burst was not processed"); return; }
        AP.GetCheckCounts(Collected, InLogic, Total);
        if (Collected != ArenaChecks || InLogic != SlotChecks || Total != SlotChecks ||
            AP.CollectedOnMap(0) != ArenaChecks || AP.CollectedOnMap(1) != 0)
        { FailTest("HUD counts after reconnect/unlock"); return; }
        if (AP.bPickupLocations)
            for (Marker = AP.FirstPickup; Marker != None; Marker = Marker.NextPickup)
                if (!AP.Progress.IsChecked(5000 + Marker.PickupIndex))
                { FailTest("pickup progress lost on reconnect"); return; }
        if (!AP.Progress.IsChecked(0) || !AP.Progress.IsChecked(LastCheck))
        { FailTest("progress lost on reconnect"); return; }
        if (AP.Progress.GetFrag(0) != AP.MatchFragLimit || AP.Progress.GetFrag(1) != 3 ||
            AP.Client.ItemIndex != ExpectedItems)
        { FailTest("duplicate item or frag history"); return; }
        if (AP.Progress.GetPendingFrag(0) != 0 || AP.Progress.GetPendingFrag(1) != 0 ||
            AP.Progress.IsPendingCheck(0) || AP.Progress.IsPendingCheck(LastCheck))
        { FailTest("confirmed progress remains in local outbox"); return; }
        if (AP.Progress.NotifiedItemIndex != ExpectedItems)
        { FailTest("received item chat history"); return; }
        if (AP.bPickupLocations)
        {
            TimerMarker = AP.FirstPickup;
            // Use an unchecked index here, after server-check assertions.
            TimerMarker.PickupIndex = 15;
            TimerMarker.Pickup.RespawnTime = 20;
            TimerMarker.Pickup.GotoState('Sleeping');
            TimerStarted = Level.TimeSeconds;
            Phase = 2;
            return;
        }
        if (!CheckReplay()) return;
        Log("AP INTEGRATION PASS");
        ConsoleCommand("exit");
        Phase = 3;
    }
    else if (Phase == 2 && Level.TimeSeconds - TimerStarted > 1.5)
    {
        Orb = TimerMarker.Location + vect(0,0,64);
        AP.bTimerThroughWalls = false;
        if (!TimerMarker.TimerVisible(Human, Orb))
        { FailTest("LOS timer hidden in clear view"); return; }
        Blocker = Spawn(class'APMarkerBlocker',,,TimerMarker.Location + vect(0,0,32));
        if (Blocker == None) { FailTest("timer blocker spawn"); return; }
        if (TimerMarker.TimerVisible(Human, Orb))
        { FailTest("LOS timer visible through blocker"); return; }
        AP.bTimerThroughWalls = true;
        if (!TimerMarker.TimerVisible(Human, Orb) || TimerMarker.OrbVisible(Human, Orb))
        { FailTest("timer toggle changed orb visibility"); return; }
        Blocker.Destroy();
        if (TimerMarker.RespawnSeconds() != 19)
        { FailTest("countdown does not follow actual sleep time: " $ TimerMarker.RespawnSeconds() $ " latent " $ TimerMarker.Pickup.LatentFloat); return; }
        AP.MinRespawnTimer = 21;
        if (TimerMarker.RespawnSeconds() != 0)
        { FailTest("short respawn timer shown"); return; }
        AP.MinRespawnTimer = 20;
        TimerMarker.PickupIndex = 0;
        if (TimerMarker.RespawnSeconds() != 0)
        { FailTest("checked pickup timer shown"); return; }
        TimerMarker.PickupIndex = 15;
        TimerMarker.Pickup.GotoState('Pickup');
        if (TimerMarker.RespawnSeconds() != 0)
        { FailTest("timer remains after respawn"); return; }
        TimerMarker.PickupIndex = 0;
        if (AP.bDeathLink)
        {
            Human.Health = 100;
            AP.ReceiveDeathLink("Other player", "Test");
            if (Human.Health > 0 || AP.bReceivingDeathLink)
            { FailTest("incoming DeathLink did not kill player"); return; }
        }
        if (!CheckReplay()) return;
        Log("AP INTEGRATION PASS");
        ConsoleCommand("exit");
        Phase = 3;
    }
}

defaultproperties
{
    bAlwaysTick=True
}
