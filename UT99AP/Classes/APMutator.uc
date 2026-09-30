class APMutator extends Mutator config(UT99AP);

var config string Host, SlotName, Password;
var config int APPort;
var config int MinRespawnTimer;
var config int MinNotify;
var config int BotSkillSpread;
var config bool bProgressionSound;
var config bool bShowPickupBoxes, bShowRespawnTimers, bShowAllRespawns;
var config bool bTimerThroughWalls;
var config bool bAutoConnect;
var APClient Client;
var APProgress Progress;
var APPickupMarker FirstPickup;
var bool bPickupLocations;
// Unlock mode: 0 legacy, 1 family, 2 pickup type.
var int PickupUnlockMode;
struct APFlag { var bool bSet; };
var APFlag Selected[82], Unlocked[82], Weapons[9], PickupFamilies[8], PickupTypes[32], PickupIncluded[4792];
var bool bReady, bHandledEnd, bMenuOpened;
var bool bReceivingDeathLink, bDeathLink;
var int StartingMap, GoalRequired, FragIncrement, MatchFragLimit, BotSkill, BotCount, CurrentMap;
var int WeaponLogicPercentage, StageWeaponMask[82], StageWeaponCount[82];
var string Status;
var string CheckSummary;
var int MapCollected[82], MapInLogic[82], MapTotal[82];
var string PickupLocationSet;
var float RetryTime;

function bool IsSelected(int I) { return Selected[I].bSet; }
function SetSelected(int I, bool Value) { Selected[I].bSet = Value; }
function bool IsUnlocked(int I) { return Unlocked[I].bSet; }
function SetUnlocked(int I, bool Value) { Unlocked[I].bSet = Value; }
function int CollectedOnMap(int I) { return MapCollected[I]; }
function int InLogicOnMap(int I) { return MapInLogic[I]; }
function int TotalOnMap(int I) { return MapTotal[I]; }
function int WeaponsOnMap(int I) { return StageWeaponCount[I]; }

function AdjustBot(Bot NewBot)
{
    local int Spread;
    local float Skill;
    Spread = Clamp(BotSkillSpread, 0, 7);
    if (Spread == 0) return;
    Skill = NewBot.Skill;
    if (!NewBot.bNovice) Skill += 4;
    NewBot.InitializeSkill(FClamp(Skill + Rand(2 * Spread + 1) - Spread, 0, 7));
}

function PostBeginPlay()
{
    local int I, MapIndex, Family;
    Super.PostBeginPlay();
    Progress = class'APProgress'.static.GetSession();
    CurrentMap = -1;
    if (APDeathMatch(Level.Game) != None || APCTF(Level.Game) != None ||
        APDomination(Level.Game) != None || APAssault(Level.Game) != None)
        for (I = 0; I < 82; I++)
            if (string(Level.Outer.Name) ~= class'APCatalog'.default.Maps[I]) CurrentMap = I;
    for (I = 0; I < class'APCatalog'.default.PickupCount; I++)
    {
        MapIndex = class'APCatalog'.static.PickupMap(I);
        Family = class'APCatalog'.static.PickupFamily(I);
        if (Family < 9) StageWeaponMask[MapIndex] = StageWeaponMask[MapIndex] | (1 << Family);
    }
    for (MapIndex = 0; MapIndex < 82; MapIndex++)
        for (Family = 0; Family < 9; Family++)
            if ((StageWeaponMask[MapIndex] & (1 << Family)) != 0) StageWeaponCount[MapIndex]++;
    Status = "Set slot and server in Mods > Archipelago";
    if (CurrentMap >= 0) Level.Game.RegisterDamageMutator(Self);
    SetTimer(1.0, true);
}

function Connect()
{
    local int I, N;
    local string Address, Scheme, PortText;
    if (Client != None) { Client.AP = None; Client.Destroy(); Client = None; }
    bReady = false;
    if (SlotName == "") { Status = "Enter your AP slot name"; return; }
    Address = Host;
    if (Left(Address, 5) ~= "ws://") { Scheme = "ws://"; Address = Mid(Address, 5); }
    else if (Left(Address, 6) ~= "wss://") { Scheme = "wss://"; Address = Mid(Address, 6); }
    if (Right(Address, 1) == "/") Address = Left(Address, Len(Address) - 1);
    I = InStr(Address, ":");
    if (I >= 0)
    {
        PortText = Mid(Address, I + 1);
        if (PortText != string(int(PortText))) { Status = "Invalid server port"; return; }
        APPort = int(PortText);
        Address = Left(Address, I);
    }
    if (Address == "" || APPort < 1 || APPort > 65535)
    { Status = "Invalid server host or port"; return; }
    for (I = 0; I < Len(Address); I++)
    {
        N = Asc(Mid(Address, I, 1));
        if (N <= 32 || N >= 127 || InStr("/:?#\\@", Mid(Address, I, 1)) >= 0)
        { Status = "Use a hostname or IPv4 address, optionally with ws:// or wss://"; return; }
    }
    bAutoConnect = true;
    SaveConfig();
    Status = "Connecting to " $ Scheme $ Address $ ":" $ APPort;
    Client = Spawn(class'APClient');
    Client.AP = Self;
    Client.ConnectTo(Scheme $ Address $ ":" $ APPort);
    RetryTime = Level.TimeSeconds + 5;
}

function Disconnect()
{
    bAutoConnect = false;
    bReady = false;
    SaveConfig();
    if (Client != None)
    {
        if (Client.Bridge != None) Client.Bridge.Disconnect();
        Client.AP = None; Client.Destroy(); Client = None;
    }
    Status = "Disconnected";
}

function Timer()
{
    local Pawn P, Best, Human;
    local bool bTie;
    local WindowConsole Console;
    if (CurrentMap >= 0 && !bHUDMutator && Level.NetMode == NM_Standalone) RegisterHUDMutator();
    if (!bMenuOpened && Level.NetMode == NM_Standalone && APDeathMatch(Level.Game) != None)
    {
        if (!APDeathMatch(Level.Game).bAPStage)
            for (P = Level.PawnList; P != None; P = P.NextPawn)
                if (PlayerPawn(P) != None && PlayerPawn(P).Player != None)
                {
                    Console = WindowConsole(PlayerPawn(P).Player.Console);
                    if (Console != None)
                    {
                        bMenuOpened = true;
                        Console.LaunchUWindow();
                        Console.Root.CreateWindow(class'APMenuWindow', 70, 15, 500, 450);
                    }
                    break;
                }
    }
    if (bAutoConnect && SlotName != "" && Level.TimeSeconds >= RetryTime &&
        (Client == None || Client.bFailed)) Connect();
    if (bReady) { UpdateCheckSummary(); ApplyFiller(); }
    if (!bReady || bHandledEnd || !IsStage() || !Level.Game.bGameEnded) return;
    bHandledEnd = true;
    for (P = Level.PawnList; P != None; P = P.NextPawn)
        if (P.bIsPlayer && P.PlayerReplicationInfo != None && !P.PlayerReplicationInfo.bIsSpectator)
        {
            if (IsHuman(P)) Human = P;
            if (Best == None || P.PlayerReplicationInfo.Score > Best.PlayerReplicationInfo.Score)
            { Best = P; bTie = false; }
            else if (P.PlayerReplicationInfo.Score == Best.PlayerReplicationInfo.Score) bTie = true;
        }
    if (Human == None) return;
    if (class'APCatalog'.default.MapMode[CurrentMap] == 0)
    {
        if (Best == Human && !bTie && Best.PlayerReplicationInfo.Score >= MatchFragLimit)
            Check(CheckIndex(CurrentMap, 0));
    }
    else if (TeamGamePlus(Level.Game) != None && Human.PlayerReplicationInfo.Team < 4 &&
        TeamGamePlus(Level.Game).Teams[Human.PlayerReplicationInfo.Team] != None &&
        TeamGamePlus(Level.Game).Teams[Human.PlayerReplicationInfo.Team].Score >=
        TeamGamePlus(Level.Game).GoalTeamScore &&
        class'APCatalog'.default.MapMode[CurrentMap] != 3)
        Check(CheckIndex(CurrentMap, 0));
    else if (APAssault(Level.Game) != None && APAssault(Level.Game).bAssaultWon &&
        APAssault(Level.Game).Attacker != None &&
        Human.PlayerReplicationInfo.Team == APAssault(Level.Game).Attacker.TeamIndex)
        Check(CheckIndex(CurrentMap, 0));
}

function bool IsHuman(Pawn P)
{
    return PlayerPawn(P) != None && P.PlayerReplicationInfo != None &&
        !P.PlayerReplicationInfo.bIsSpectator;
}

function bool IsStage()
{
    if (CurrentMap < 0 || !bReady) return false;
    return CanEnterMap(CurrentMap) &&
        ((APDeathMatch(Level.Game) != None && APDeathMatch(Level.Game).bAPStage) ||
         (APCTF(Level.Game) != None && APCTF(Level.Game).bAPStage) ||
         (APDomination(Level.Game) != None && APDomination(Level.Game).bAPStage) ||
         (APAssault(Level.Game) != None && APAssault(Level.Game).bAPStage));
}

function DisableStage()
{
    if (APDeathMatch(Level.Game) != None) APDeathMatch(Level.Game).bAPStage = false;
    if (APCTF(Level.Game) != None) APCTF(Level.Game).bAPStage = false;
    if (APDomination(Level.Game) != None) APDomination(Level.Game).bAPStage = false;
    if (APAssault(Level.Game) != None) APAssault(Level.Game).bAPStage = false;
}

function int StageWeaponsNeeded(int MapIndex)
{
    return (StageWeaponCount[MapIndex] * WeaponLogicPercentage + 99) / 100;
}

function int StageWeaponsHeld(int MapIndex)
{
    local int I, Count;
    for (I = 0; I < 9; I++)
        if ((StageWeaponMask[MapIndex] & (1 << I)) != 0 && Weapons[I].bSet) Count++;
    return Count;
}

function bool CanEnterMap(int MapIndex)
{
    return MapIndex >= 0 && MapIndex < 82 && Selected[MapIndex].bSet &&
        Unlocked[MapIndex].bSet && StageWeaponsHeld(MapIndex) >= StageWeaponsNeeded(MapIndex);
}

function InventoryReady()
{
    local Pawn P;
    local DeathMatchPlus Game;
    local TeamGamePlus TeamGame;
    local APPickupMarker Marker;
    if (CurrentMap < 0) { UpdateCheckSummary(); return; }
    Game = DeathMatchPlus(Level.Game);
    if (Game != None)
    {
        Game.FragLimit = 0;
        if (class'APCatalog'.default.MapMode[CurrentMap] == 0)
            Game.FragLimit = MatchFragLimit;
        if (class'APCatalog'.default.MapMode[CurrentMap] != 3)
        { Game.TimeLimit = 0; Game.RemainingTime = 0; }
        Game.MinPlayers = BotCount + 1;
        Game.RemainingBots = Max(0, BotCount - Game.NumBots);
        Game.BotConfig.Difficulty = BotSkill;
        if (!IsStage()) { Game.MinPlayers = 0; Game.RemainingBots = 0; }
        if (class'APCatalog'.default.MapMode[CurrentMap] != 3)
            Game.GameReplicationInfo.RemainingTime = 0;
        TournamentGameReplicationInfo(Game.GameReplicationInfo).FragLimit = Game.FragLimit;
        TeamGame = TeamGamePlus(Game);
        if (TeamGame != None)
        {
            if (class'APCatalog'.default.MapMode[CurrentMap] == 1) TeamGame.GoalTeamScore = 3;
            else if (class'APCatalog'.default.MapMode[CurrentMap] == 2) TeamGame.GoalTeamScore = 100;
            TournamentGameReplicationInfo(Game.GameReplicationInfo).GoalTeamScore = TeamGame.GoalTeamScore;
        }
    }
    for (P = Level.PawnList; P != None; P = P.NextPawn)
        if (IsHuman(P) && P.Health > 0) ModifyPlayer(P);
    InitPickupMarkers();
    for (Marker = FirstPickup; Marker != None; Marker = Marker.NextPickup)
        Marker.UpdateFamilyVisibility();
    ApplyFiller();
    UpdateCheckSummary();
    TeamScoreProgress();
}

function ApplyFiller()
{
    local Pawn P;
    local Inventory Inv, Armor;
    local Ammo A;
    local int I;
    local bool bChanged, bHasArmor;
    if (!IsStage()) return;
    for (P = Level.PawnList; P != None; P = P.NextPawn)
        if (IsHuman(P) && P.Health > 0) break;
    if (P == None) return;
    if (Progress.PendingHealth > 0 && P.Health < 100)
    { P.Health++; Progress.PendingHealth--; bChanged = true; }
    if (Progress.PendingArmor > 0)
    {
        for (Inv = P.Inventory; Inv != None; Inv = Inv.Inventory)
            if (Inv.bIsAnArmor)
            {
                bHasArmor = true;
                if (Inv.Charge < Inv.Default.Charge) { Armor = Inv; break; }
            }
        if (Armor == None && !bHasArmor)
        {
            Armor = Spawn(class'ThighPads', P,, P.Location);
            if (Armor != None) { Armor.Charge = 0; Armor.GiveTo(P); }
        }
        if (Armor != None)
        { Armor.Charge++; Progress.PendingArmor--; bChanged = true; }
    }
    for (I = 0; I < 9; I++)
        if (Progress.PendingWeaponAmmo[I] > 0)
        {
            A = None;
            for (Inv = P.Inventory; Inv != None; Inv = Inv.Inventory)
                if (string(Inv.Class) ~= class'APCatalog'.default.AmmoClasses[I])
                { A = Ammo(Inv); break; }
            if (A != None && A.AddAmmo(class'APCatalog'.default.AmmoFillerAmounts[I]))
            { Progress.PendingWeaponAmmo[I]--; bChanged = true; }
        }
    if (bChanged) Progress.SaveConfig();
}

function bool PickupUnlocked(int PickupIndex)
{
    local int Family;
    if (PickupUnlockMode == 0) return true;
    if (!bReady || PickupIndex < 0 || PickupIndex >= class'APCatalog'.default.PickupCount)
        return false;
    if (PickupUnlockMode == 2)
        return PickupTypes[class'APCatalog'.static.PickupType(PickupIndex)].bSet;
    Family = class'APCatalog'.static.PickupFamily(PickupIndex);
    if (Family < 9) return Weapons[Family].bSet;
    if (Family < 17) return PickupFamilies[Family - 9].bSet;
    return false;
}

function ClearPickupMarkers()
{
    local APPickupMarker Marker;
    while (FirstPickup != None)
    {
        Marker = FirstPickup;
        FirstPickup = Marker.NextPickup;
        Marker.Destroy();
    }
}

function InitPickupMarkers()
{
    local int I;
    local Inventory Item, Candidate;
    local APPickupMarker Marker;
    if (!bPickupLocations || !IsStage() || FirstPickup != None) return;
    for (I = 0; I < class'APCatalog'.default.PickupCount; I++)
        if (PickupIncluded[I].bSet && class'APCatalog'.static.PickupMap(I) == CurrentMap)
        {
            // scan positions once per arena
            // TODO: index for large custom maps
            Item = None;
            foreach AllActors(class'Inventory', Candidate)
                if (Candidate.Owner == None && !Candidate.bDeleteMe && !Candidate.bHeldItem && !Candidate.bTossedOut &&
                    string(Candidate.Class) ~= class'APCatalog'.static.PickupClass(I) &&
                    VSize(Candidate.Location - class'APCatalog'.static.PickupPosition(I)) < 2)
                { Item = Candidate; break; }
            if (Item == None)
            {
                Status = "Pickup catalog mismatch; install the supported stock map";
                Log("AP: missing pickup " $ class'APCatalog'.static.PickupLabel(I));
                bReady = false;
                ClearPickupMarkers();
                return;
            }
            Marker = Spawn(class'APPickupMarker',,,Item.Location);
            if (Marker == None)
            {
                Status = "Could not create AP pickup marker";
                bReady = false;
                ClearPickupMarkers();
                return;
            }
            Marker.AP = Self;
            Marker.Pickup = Item;
            Marker.PickupIndex = I;
            Marker.BoxExtent.X = Item.CollisionRadius + 4;
            Marker.BoxExtent.Y = Marker.BoxExtent.X;
            Marker.BoxExtent.Z = Item.CollisionHeight + 4;
            Marker.SetCollisionSize(Item.CollisionRadius, Item.CollisionHeight);
            Marker.SetBase(Item.Base);
            Marker.SetTimer(0.25, true);
            Marker.NextPickup = FirstPickup;
            FirstPickup = Marker;
        }
}

simulated event PostRender(Canvas C)
{
    local PlayerPawn Viewer;
    local WindowConsole WC;
    local Actor Camera;
    local vector Eye;
    local rotator ViewRotation;
    local APPickupMarker Marker;
    foreach AllActors(class'PlayerPawn', Viewer) if (Viewer.Player != None) break;
    if (Viewer != None)
    {
        class'APConsoleTextArea'.static.Install(Viewer, C);
        WC = WindowConsole(Viewer.Player.Console);
        if (WC != None && (WC.bShowConsole || WC.bUWindowActive))
        {
            if (NextHUDMutator != None) NextHUDMutator.PostRender(C);
            return;
        }
    }
    if (IsStage() && Client != None && Client.Bridge != None)
    {
        if (Viewer != None)
        {
            Viewer.PlayerCalcView(Camera, Eye, ViewRotation);
            for (Marker = FirstPickup; Marker != None; Marker = Marker.NextPickup)
                if (!Progress.IsChecked(5000 + Marker.PickupIndex) &&
                    PickupUnlocked(Marker.PickupIndex))
                    Client.Bridge.DrawPickupMarker(C, Marker.Location, Marker.BoxExtent,
                        class'APPickupMarker'.static.ClassificationColor(Marker.ItemFlags),
                        bShowPickupBoxes, Marker.OrbVisible(Viewer, Eye));
            if (APAssault(Level.Game) != None) DrawAssaultObjectives(C, Viewer);
        }
    }
    if (Viewer != None) DrawCheckSummary(C, Viewer, Eye);
    if (NextHUDMutator != None) NextHUDMutator.PostRender(C);
}

function int AssaultObjectiveIndex(FortStandard Fort)
{
    local int I;
    if (Fort == None || CurrentMap < 0) return -1;
    for (I = 0; I < class'APCatalog'.default.ObjectiveCount; I++)
        if (class'APCatalog'.static.ObjectiveMap(I) == CurrentMap &&
            class'APCatalog'.static.ObjectiveActor(I) ~= string(Fort.Name) &&
            !Progress.IsChecked(CheckIndex(CurrentMap, class'APCatalog'.static.ObjectiveStep(I))))
            return I;
    return -1;
}

simulated function DrawAssaultObjectives(Canvas C, PlayerPawn Viewer)
{
    local FortStandard Fort;
    local ChallengeHUD HUD;
    local int I;
    local vector Extent, Position;
    local float X, Y, W, H, SavedX, SavedY, SavedYL;
    local font SavedFont;
    local color SavedColor, Gold;
    local byte SavedStyle;
    local bool SavedCenter;
    local string Label;
    SavedFont = C.Font;
    SavedColor = C.DrawColor;
    SavedStyle = C.Style;
    SavedCenter = C.bCenter;
    SavedX = C.CurX; SavedY = C.CurY; SavedYL = C.CurYL;
    HUD = ChallengeHUD(Viewer.MyHUD);
    if (HUD != None && HUD.MyFonts != None) C.Font = HUD.MyFonts.GetSmallestFont(C.SizeX);
    else C.Font = C.MedFont;
    C.Style = 1;
    C.bCenter = false;
    Gold.R = 255; Gold.G = 210; Gold.B = 64;
    foreach AllActors(class'FortStandard', Fort)
    {
        I = AssaultObjectiveIndex(Fort);
        if (I < 0) continue;
        Extent = vect(0,0,1) * (Fort.CollisionHeight + 8);
        Position = Fort.Location + Extent + vect(0,0,12);
        Client.Bridge.DrawPickupMarker(C, Fort.Location, Extent, Gold, false, true);
        if (!Client.Bridge.ProjectPoint(C, Position, X, Y)) continue;
        Label = class'APCatalog'.static.ObjectiveStep(I) $ ". " $
            class'APCatalog'.static.ObjectiveLabel(I);
        C.TextSize(Label, W, H);
        X = FClamp(X - W / 2, 0, Max(0, C.SizeX - W));
        Y = FClamp(Y - H - 12, 0, Max(0, C.SizeY - H));
        C.DrawColor.R = 0; C.DrawColor.G = 0; C.DrawColor.B = 0;
        C.SetPos(X + 1, Y + 1);
        C.DrawText(Label, false);
        C.DrawColor = Gold;
        C.SetPos(X, Y);
        C.DrawText(Label, false);
    }
    C.Font = SavedFont;
    C.DrawColor = SavedColor;
    C.Style = SavedStyle;
    C.bCenter = SavedCenter;
    C.SetPos(SavedX, SavedY);
    C.CurYL = SavedYL;
}

function GetCheckCounts(out int Collected, out int InLogic, out int Total)
{
    local int I, MapIndex, Milestone;
    local int MapAccessible[82];
    Collected = 0;
    InLogic = 0;
    Total = 0;
    for (I = 0; I < 82; I++)
    {
        MapCollected[I] = 0; MapInLogic[I] = 0; MapTotal[I] = 0;
        if (CanEnterMap(I)) MapAccessible[I] = 1;
    }
    for (I = 0; I < 15000; I++)
        if (DecodeCheck(I, MapIndex, Milestone))
        {
            Total++;
            MapTotal[MapIndex]++;
            if (MapAccessible[MapIndex] != 0 && (Milestone >= 0 || PickupUnlocked(I - 5000)))
            { InLogic++; MapInLogic[MapIndex]++; }
            if (Progress.IsChecked(I)) { Collected++; MapCollected[MapIndex]++; }
        }
}

function UpdateCheckSummary()
{
    local int Collected, InLogic, Total;
    GetCheckCounts(Collected, InLogic, Total);
    if (IsStage())
    {
        CheckSummary = "AP checks (" $ class'APCatalog'.default.Maps[CurrentMap] $ "): " $
            MapCollected[CurrentMap] $ " / ";
        if (PickupUnlockMode != 0 || WeaponLogicPercentage > 0)
            CheckSummary $= MapInLogic[CurrentMap] $ " (" $ MapTotal[CurrentMap] $ ")";
        else CheckSummary $= MapTotal[CurrentMap];
    }
    else
        CheckSummary = "AP seed checks: " $ Collected $ " / " $ InLogic $ " (" $ Total $ ")";
}

simulated function DrawCheckSummary(Canvas C, PlayerPawn Viewer, vector Eye)
{
    local font SavedFont;
    local color SavedColor;
    local byte SavedStyle;
    local bool SavedCenter;
    local float SavedX, SavedY, SavedYL, X, Y, Distance, NearestDistance;
    local int Seconds;
    local APPickupMarker Marker, CenterMarker;
    local Inventory Item, CenterItem;
    local ChallengeHUD HUD;
    local string Text;
    SavedFont = C.Font;
    SavedColor = C.DrawColor;
    SavedStyle = C.Style;
    SavedCenter = C.bCenter;
    SavedX = C.CurX;
    SavedY = C.CurY;
    SavedYL = C.CurYL;
    HUD = ChallengeHUD(Viewer.MyHUD);
    if (HUD != None && HUD.MyFonts != None) C.Font = HUD.MyFonts.GetSmallestFont(C.SizeX);
    else C.Font = C.MedFont;
    C.Style = 1;
    C.bCenter = false;
    if (bShowRespawnTimers && IsStage() && Client != None && Client.Bridge != None)
    {
        NearestDistance = 64;
        if (bShowAllRespawns)
        {
            foreach AllActors(class'Inventory', Item)
            {
                Distance = VSize(Viewer.Location - Item.Location);
                if (Distance <= NearestDistance && AllRespawnSeconds(Item) > 0 &&
                    TimerItemVisible(Viewer, Eye, Item))
                { CenterItem = Item; NearestDistance = Distance; }
            }
        }
        else
        {
            for (Marker = FirstPickup; Marker != None; Marker = Marker.NextPickup)
            {
                Distance = VSize(Viewer.Location - Marker.Location);
                if (Distance <= NearestDistance && Marker.RespawnSeconds() > 0 &&
                    Marker.TimerVisible(Viewer, Eye))
                { CenterMarker = Marker; NearestDistance = Distance; }
            }
        }
        if (bShowAllRespawns)
        {
            foreach AllActors(class'Inventory', Item)
            {
                Seconds = AllRespawnSeconds(Item);
                if (Seconds <= 0 || !TimerItemVisible(Viewer, Eye, Item)) continue;
                if (Item == CenterItem) { X = C.SizeX / 2; Y = C.SizeY / 2; }
                else if (VSize(Viewer.Location - Item.Location) <= 64 ||
                    !Client.Bridge.ProjectPoint(C, Item.Location, X, Y)) continue;
                DrawTimerLabel(C, Seconds, X, Y);
            }
        }
        else
        {
            for (Marker = FirstPickup; Marker != None; Marker = Marker.NextPickup)
            {
                Seconds = Marker.RespawnSeconds();
                if (Seconds > 0 && Marker.TimerVisible(Viewer, Eye))
                {
                    if (Marker == CenterMarker) { X = C.SizeX / 2; Y = C.SizeY / 2; }
                    else if (VSize(Viewer.Location - Marker.Location) <= 64 ||
                        !Client.Bridge.ProjectPoint(C, Marker.Location, X, Y)) continue;
                    DrawTimerLabel(C, Seconds, X, Y);
                }
            }
        }
    }
    Text = CheckSummary;
    if (!bReady) Text = "AP checks: waiting for connection";
    X = FMax(12, C.SizeX * 0.015);
    Y = C.SizeY * 0.78;
    C.DrawColor.R = 0;
    C.DrawColor.G = 0;
    C.DrawColor.B = 0;
    C.SetPos(X + 1, Y + 1);
    C.DrawText(Text, false);
    C.DrawColor.R = 240;
    C.DrawColor.G = 240;
    C.DrawColor.B = 240;
    C.SetPos(X, Y);
    C.DrawText(Text, false);
    C.Font = SavedFont;
    C.DrawColor = SavedColor;
    C.Style = SavedStyle;
    C.bCenter = SavedCenter;
    C.SetPos(SavedX, SavedY);
    C.CurYL = SavedYL;
}

function ModifyPlayer(Pawn Other)
{
    local int I, J;
    local Inventory Inv, NextInv;
    local bool bAllowed;
    Super.ModifyPlayer(Other);
    if (!IsHuman(Other)) return;
    // Reconcile inventory on slot change, reconnect, or respawn.
    for (Inv = Other.Inventory; Inv != None; Inv = NextInv)
    {
        NextInv = Inv.Inventory;
        for (I = 0; I < 9; I++)
            if (string(Inv.Class) ~= class'APCatalog'.default.WeaponClasses[I])
            {
                bAllowed = bReady && Weapons[I].bSet;
                if (!bAllowed)
                {
                    if (Other.Weapon == Inv) Other.Weapon = None;
                    Other.DeleteInventory(Inv);
                    Inv.Destroy();
                }
                break;
            }
    }
    if (!IsStage()) return;
    if (Other.Weapon == None) Other.Weapon = Weapon(Other.FindInventoryType(class'Enforcer'));
    for (J = 0; J < 9; J++)
        if (Weapons[J].bSet) DeathMatchPlus(Level.Game).GiveWeapon(Other, class'APCatalog'.default.WeaponClasses[J]);
    if (Other.Weapon == None) Other.SwitchToBestWeapon();
}

function bool HandlePickupQuery(Pawn Other, Inventory Item, out byte bAllowPickup)
{
    local int I;
    local APPickupMarker Marker;
    for (Marker = FirstPickup; Marker != None; Marker = Marker.NextPickup)
        if (Marker.Pickup == Item)
        {
            if (PlayerPawn(Other) != None && !PickupUnlocked(Marker.PickupIndex))
            { bAllowPickup = 0; return true; }
            if (IsHuman(Other)) Marker.Touch(Other);
            break;
        }
    if (IsHuman(Other))
    {
        for (I = 0; I < 9; I++)
            if (string(Item.Class) ~= class'APCatalog'.default.WeaponClasses[I])
                if (!bReady || !Weapons[I].bSet) { bAllowPickup = 0; return true; }
    }
    return Super.HandlePickupQuery(Other, Item, bAllowPickup);
}

function MutatorTakeDamage(out int Damage, Pawn Victim, Pawn InstigatedBy,
    out vector HitLocation, out vector Momentum, name DamageType)
{
    Super.MutatorTakeDamage(Damage, Victim, InstigatedBy, HitLocation, Momentum, DamageType);
    if (!IsStage()) { Damage = 0; Momentum = vect(0,0,0); }
}

function ScoreKill(Pawn Killer, Pawn Other)
{
    local int Milestone;
    Super.ScoreKill(Killer, Other);
    if (bDeathLink && !bReceivingDeathLink && IsStage() && IsHuman(Other) &&
        Client != None && Client.Bridge != None) Client.Bridge.SendDeathLink();
    if (!IsStage() || Level.Game.bGameEnded || !IsHuman(Killer) ||
        Other == None || Killer == Other || !Other.bIsPlayer || Other.PlayerReplicationInfo == None ||
        Other.PlayerReplicationInfo.bIsSpectator) return;
    if (CurrentMap >= 37 &&
        Killer.PlayerReplicationInfo.Team == Other.PlayerReplicationInfo.Team) return;
    if (Progress.GetFrag(CurrentMap) >= MatchFragLimit) return;
    Progress.SetLocalFrag(CurrentMap, Progress.GetFrag(CurrentMap) + 1);
    Client.SendFrag(CurrentMap, Progress.GetFrag(CurrentMap));
    Milestone = Progress.GetFrag(CurrentMap) / FragIncrement;
    if (Milestone > 0 && Progress.GetFrag(CurrentMap) % FragIncrement == 0)
    {
        if (CurrentMap < 37) Check(CheckIndex(CurrentMap, Milestone));
        else Check(TeamFragIndex(CurrentMap, Milestone));
    }
}

function int TeamFragIndex(int MapIndex, int Milestone)
{
    return 10000 + (MapIndex - 37) * 101 + Milestone;
}

function int CheckIndex(int MapIndex, int Milestone)
{
    if (MapIndex < 37) return MapIndex * 101 + Milestone;
    return 3737 + (MapIndex - 37) * 20 + Milestone;
}

function ObjectiveProgress(int Step)
{
    local int I;
    if (!IsStage() ||
        (class'APCatalog'.default.MapMode[CurrentMap] != 1 &&
         class'APCatalog'.default.MapMode[CurrentMap] != 2)) return;
    for (I = 1; I <= Min(Step, class'APCatalog'.default.MapObjectiveCount[CurrentMap]); I++)
        Check(CheckIndex(CurrentMap, I));
}

function TeamScoreProgress()
{
    local Pawn P;
    local TeamGamePlus Game;
    local float Score;
    Game = TeamGamePlus(Level.Game);
    if (!IsStage() || Game == None) return;
    for (P = Level.PawnList; P != None; P = P.NextPawn)
        if (IsHuman(P) && P.PlayerReplicationInfo.Team < 4 &&
            Game.Teams[P.PlayerReplicationInfo.Team] != None)
        {
            Score = Game.Teams[P.PlayerReplicationInfo.Team].Score;
            if (class'APCatalog'.default.MapMode[CurrentMap] == 1)
                ObjectiveProgress(int(Score));
            else if (class'APCatalog'.default.MapMode[CurrentMap] == 2)
                ObjectiveProgress(int(Score / 25));
            return;
        }
}

function ObjectiveFort(name ActorName)
{
    local int I;
    if (!IsStage() || class'APCatalog'.default.MapMode[CurrentMap] != 3) return;
    for (I = 0; I < class'APCatalog'.default.ObjectiveCount; I++)
        if (class'APCatalog'.static.ObjectiveMap(I) == CurrentMap &&
            class'APCatalog'.static.ObjectiveActor(I) ~= string(ActorName))
        { Check(CheckIndex(CurrentMap, class'APCatalog'.static.ObjectiveStep(I))); return; }
}

function bool DecodeCheck(int Index, out int MapIndex, out int Milestone)
{
    if (Index >= 10000 && Index < 14545)
    {
        MapIndex = 37 + (Index - 10000) / 101;
        Milestone = (Index - 10000) % 101;
        return Milestone > 0 && Milestone <= MatchFragLimit / FragIncrement &&
            Selected[MapIndex].bSet;
    }
    if (Index >= 5000 && Index < 5000 + class'APCatalog'.default.PickupCount)
    {
        MapIndex = class'APCatalog'.static.PickupMap(Index - 5000);
        Milestone = -1;
        return bPickupLocations && PickupIncluded[Index - 5000].bSet && Selected[MapIndex].bSet;
    }
    if (Index < 0 || Index >= 4637) return false;
    if (Index < 3737)
    { MapIndex = Index / 101; Milestone = Index % 101; }
    else
    { MapIndex = 37 + (Index - 3737) / 20; Milestone = (Index - 3737) % 20; }
    if (!Selected[MapIndex].bSet) return false;
    if (MapIndex < 37) return Milestone <= MatchFragLimit / FragIncrement;
    return Milestone <= class'APCatalog'.default.MapObjectiveCount[MapIndex];
}

function Check(int Index)
{
    local int MapIndex, Milestone;
    if (!bReady || !DecodeCheck(Index, MapIndex, Milestone) || Progress.IsChecked(Index)) return;
    if (Milestone < 0 && !PickupUnlocked(Index - 5000)) return;
    Progress.MarkChecked(Index);
    if (Milestone == 0)
    {
        Chat("Arena cleared: " $ class'APCatalog'.default.Maps[MapIndex]);
        if (WinCount() == GoalRequired) Chat("Seed goal complete!");
    }
    Client.Bridge.SendLocationCheck(19991000 + Index);
    if (Milestone == 0) Client.SendGoal();
}

function ItemNotice(string ItemName, string SenderName, int Flags, optional bool bSelf, optional string LocationName)
{
    local APMessageData M;
    local PlayerPawn P;
    if (bProgressionSound && bReady && (Flags & 1) != 0)
        foreach AllActors(class'PlayerPawn', P)
            if (P.Player != None) { P.ClientPlaySound(sound'Botpack.CTF.CaptureSound2',, true); break; }
    if (class'APItemMessage'.static.Rank(Flags) < Clamp(MinNotify, 0, 2)) return;
    M = new(None) class'APMessageData';
    M.Add("AP: [" $ class'APItemMessage'.static.Label(Flags) $ "] Received ");
    M.Add(ItemName, 2, Flags);
    M.Add(" from ");
    M.Add(SenderName, 3, 0, bSelf);
    if (LocationName != "") { M.Add(" at "); M.Add(LocationName, 1); }
    DisplayMessage(M, Mid(M.Text, 4));
}

function NativeChat(string Packet)
{
    local APMessageData M;
    local string Parts, Entry, Text;
    local int P, Flags;
    local bool bItem;
    Text = class'APJson'.static.Decode(class'APJson'.static.Get(Packet, "text"));
    if (class'APJson'.static.Get(Packet, "command_result") == "true")
    {
        // Split long server-formatted replies.
        while (Text != "")
        {
            P = InStr(Text, Chr(10));
            if (P < 0) P = Len(Text);
            P = Min(P, 1000);
            if (P > 0) Chat(Left(Text, P));
            Text = Mid(Text, P);
            if (Left(Text, 1) == Chr(10)) Text = Mid(Text, 1);
        }
        return;
    }
    bItem = class'APJson'.static.Get(Packet, "item_notice") == "true";
    Flags = int(class'APJson'.static.Get(Packet, "flags"));
    if (bItem && class'APItemMessage'.static.Rank(Flags) < Clamp(MinNotify, 0, 2)) return;
    M = new(None) class'APMessageData';
    if (bItem) M.Add("AP: [" $ class'APItemMessage'.static.Label(Flags) $ "] ");
    else M.Add("AP: ");
    Parts = class'APJson'.static.Get(Packet, "parts");
    if (Left(Parts, 1) != "[") M.Add(Text);
    else while (class'APJson'.static.Next(Parts, P, Entry))
        M.Add(class'APJson'.static.Decode(class'APJson'.static.Get(Entry, "text")),
            int(class'APJson'.static.Get(Entry, "kind")), int(class'APJson'.static.Get(Entry, "flags")),
            class'APJson'.static.Get(Entry, "self") == "true");
    DisplayMessage(M, Text);
}

function Chat(string Text)
{
    local APMessageData M;
    M = new(None) class'APMessageData';
    M.Add("AP: "); M.Add(Text);
    DisplayMessage(M, Text);
}

function DisplayMessage(APMessageData M, string LogText)
{
    local PlayerPawn P;
    local WindowConsole WC;
    local APConsoleRow Row;
    Log("AP: " $ class'APMessageData'.static.Clean(LogText));
    // Bypass UT chat flood limits for local AP notices
    foreach AllActors(class'PlayerPawn', P)
        if (P.Player != None)
        {
            class'APConsoleTextArea'.static.Install(P);
            if (P.Player.Console != None)
            {
                P.Player.Console.Message(P.PlayerReplicationInfo, M.Text, 'Event');
                WC = WindowConsole(P.Player.Console);
                if (WC != None && WC.ConsoleWindow != None)
                {
                    Row = APConsoleRow(UWindowConsoleClientWindow(WC.ConsoleWindow.ClientArea).TextArea.List.Last);
                    if (Row != None) Row.Message = M;
                }
            }
            if (P.myHUD != None) P.myHUD.LocalizedMessage(class'APItemMessage', 0, None, None, M, M.Text);
        }
}

function int WinCount()
{
    local int I, Count;
    for (I = 0; I < 82; I++)
        if (Selected[I].bSet && Progress.IsChecked(CheckIndex(I, 0))) Count++;
    return Count;
}

function StartMap(int Index, PlayerPawn Sender)
{
    local string URL, GameClass;
    if (Sender == None || !bReady || Index < 0 || Index >= 82) return;
    if (!Selected[Index].bSet || !Unlocked[Index].bSet) { Sender.ClientMessage("AP: map is locked"); return; }
    if (!CanEnterMap(Index))
    {
        Sender.ClientMessage("AP: need " $ StageWeaponsNeeded(Index) $ "/" $ StageWeaponCount[Index]
            $ " arena weapons; have " $ StageWeaponsHeld(Index));
        return;
    }
    if (Level.NetMode != NM_Standalone)
    { Sender.ClientMessage("AP: launch a local standalone bot match"); return; }
    if (Index < 37) GameClass = "UT99AP.APDeathMatch";
    else if (class'APCatalog'.default.MapMode[Index] == 1) GameClass = "UT99AP.APCTF";
    else if (class'APCatalog'.default.MapMode[Index] == 2) GameClass = "UT99AP.APDomination";
    else GameClass = "UT99AP.APAssault";
    URL = class'APCatalog'.default.Maps[Index] $ "?Game=" $ GameClass $ "?APStage=1?Difficulty="
        $ BotSkill $ "?MinPlayers=" $ (BotCount + 1);
    if (Index < 37) URL $= "?FragLimit=" $ MatchFragLimit $ "?TimeLimit=0";
    else if (class'APCatalog'.default.MapMode[Index] == 1) URL $= "?GoalTeamScore=3?TimeLimit=0";
    else if (class'APCatalog'.default.MapMode[Index] == 2) URL $= "?GoalTeamScore=100?TimeLimit=0";
    Sender.ClientTravel(URL, TRAVEL_Absolute, false);
}

function Mutate(string S, PlayerPawn Sender)
{
    local int I;
    local string Value;
    // Only local player can run ap commands
    if (Sender == None || Level.NetMode != NM_Standalone) return;
    if (Left(S, 7) ~= "ap say ") SendServerCommand(Mid(S, 7));
    else if (S ~= "ap connect") Connect();
    else if (Left(S, 12) ~= "ap minnotify")
    {
        if (Len(S) > 12)
        {
            if (Mid(S, 12) != " 0" && Mid(S, 12) != " 1" && Mid(S, 12) != " 2")
            { Sender.ClientMessage("Usage: mutate ap minnotify 0|1|2"); return; }
            MinNotify = int(Mid(S, 13));
            SaveConfig();
        }
        Sender.ClientMessage("AP minnotify: " $ Clamp(MinNotify, 0, 2) $ " (0=all, 1=useful+, 2=progression)");
    }
    else if (Left(S, 14) ~= "ap skillspread")
    {
        if (Len(S) > 14)
        {
            Value = Mid(S, 15);
            if (Mid(S, 14, 1) != " " || Value != string(Clamp(int(Value), 0, 7)))
            { Sender.ClientMessage("Usage: mutate ap skillspread 0..7"); return; }
            BotSkillSpread = int(Value);
            SaveConfig();
        }
        Sender.ClientMessage("AP bot skill spread: +/-" $ Clamp(BotSkillSpread, 0, 7) $ " (new bots only)");
    }
    else if (S ~= "ap timerthroughwalls" || S ~= "ap timerthroughwalls 0" || S ~= "ap timerthroughwalls 1")
    {
        if (S ~= "ap timerthroughwalls") bTimerThroughWalls = !bTimerThroughWalls;
        else bTimerThroughWalls = Right(S, 1) == "1";
        SaveConfig();
        Sender.ClientMessage("AP timers through walls: " $ bTimerThroughWalls);
    }
    else if (S ~= "ap pickupboxes" || S ~= "ap pickupboxes 0" || S ~= "ap pickupboxes 1")
    {
        if (S ~= "ap pickupboxes") bShowPickupBoxes = !bShowPickupBoxes;
        else bShowPickupBoxes = Right(S, 1) == "1";
        SaveConfig();
        Sender.ClientMessage("AP pickup boxes: " $ bShowPickupBoxes);
    }
    else if (S ~= "ap respawntimers" || S ~= "ap respawntimers 0" || S ~= "ap respawntimers 1")
    {
        if (S ~= "ap respawntimers") bShowRespawnTimers = !bShowRespawnTimers;
        else bShowRespawnTimers = Right(S, 1) == "1";
        SaveConfig();
        Sender.ClientMessage("AP respawn timers: " $ bShowRespawnTimers);
    }
    else if (S ~= "ap allrespawns" || S ~= "ap allrespawns 0" || S ~= "ap allrespawns 1")
    {
        if (S ~= "ap allrespawns") bShowAllRespawns = !bShowAllRespawns;
        else bShowAllRespawns = Right(S, 1) == "1";
        SaveConfig();
        Sender.ClientMessage("AP all pickup timers: " $ bShowAllRespawns);
    }
    else if (S ~= "ap progressionsound" || S ~= "ap progressionsound 0" || S ~= "ap progressionsound 1")
    {
        if (S ~= "ap progressionsound") bProgressionSound = !bProgressionSound;
        else bProgressionSound = Right(S, 1) == "1";
        SaveConfig();
        Sender.ClientMessage("AP progression sound: " $ bProgressionSound);
    }
    else if (S ~= "ap disconnect") Disconnect();
    else if (S ~= "ap status") Sender.ClientMessage("AP: " $ Status $ " | Wins " $ WinCount() $ "/" $ GoalRequired);
    else if (S ~= "ap maps")
    {
        for (I = 0; I < 82; I++)
            if (Selected[I].bSet) Sender.ClientMessage(class'APCatalog'.default.Maps[I] $ " unlocked="
                $ Unlocked[I].bSet $ " won=" $ Progress.IsChecked(CheckIndex(I, 0)));
    }
    else if (Left(S, 9) ~= "ap start ")
    {
        for (I = 0; I < 82; I++)
            if (Mid(S, 9) ~= class'APCatalog'.default.Maps[I]) StartMap(I, Sender);
    }
    else if (Left(S, 8) ~= "ap slot ") { SlotName = Mid(S, 8); SaveConfig(); }
    else if (Left(S, 8) ~= "ap host ") { Host = Mid(S, 8); SaveConfig(); }
    else if (Left(S, 8) ~= "ap port ") { APPort = int(Mid(S, 8)); SaveConfig(); }
    else if (Left(S, 12) ~= "ap password ") { Password = Mid(S, 12); SaveConfig(); }
    else Super.Mutate(S, Sender);
}

function ReceiveDeathLink(string Source, string Cause)
{
    local PlayerPawn P;
    if (!bDeathLink || !IsStage()) return;
    foreach AllActors(class'PlayerPawn', P)
        if (IsHuman(P) && P.Health > 0)
        {
            if (Cause != "") Chat("DeathLink from " $ Source $ ": " $ Cause);
            else Chat("DeathLink from " $ Source);
            bReceivingDeathLink = true;
            P.Health = 0;
            P.Died(None, 'DeathLink', P.Location);
            bReceivingDeathLink = false;
            break;
        }
}

simulated function int AllRespawnSeconds(Inventory Item)
{
    local APPickupMarker Marker;
    if (Item == None || Item.bDeleteMe || Item.Owner != None || Item.bHeldItem ||
        !Item.IsInState('Sleeping') || Item.RespawnTime < Clamp(MinRespawnTimer, 0, 600)) return 0;
    // all-item view scans markers
    // TODO: index by pickup actor for large pools
    for (Marker = FirstPickup; Marker != None; Marker = Marker.NextPickup)
        if (Marker.Pickup == Item && !PickupUnlocked(Marker.PickupIndex)) return 0;
    return Max(1, int(Item.LatentFloat + 0.999));
}

simulated function bool TimerItemVisible(PlayerPawn Viewer, vector Eye, Inventory Item)
{
    local vector HitLocation, HitNormal;
    local Actor Hit;
    if (bTimerThroughWalls) return true;
    Hit = Viewer.Trace(HitLocation, HitNormal, Item.Location, Eye, true);
    return Hit == None || Hit == Item;
}

simulated function DrawTimerLabel(Canvas C, int Seconds, float X, float Y)
{
    local float W, H;
    local string Text;
    Text = string(Seconds) $ "s";
    C.StrLen(Text, W, H);
    C.DrawColor.R = 0; C.DrawColor.G = 0; C.DrawColor.B = 0;
    C.SetPos(X - W / 2 + 1, Y - H / 2 + 1);
    C.DrawText(Text, false);
    C.DrawColor.R = 255; C.DrawColor.G = 255; C.DrawColor.B = 255;
    C.SetPos(X - W / 2, Y - H / 2);
    C.DrawText(Text, false);
}

function ResetPickupLocations()
{
    local int I;
    for (I = 0; I < class'APCatalog'.default.PickupCount; I++)
        PickupIncluded[I].bSet = false;
}

function bool AddPickupLocation(int Index)
{
    if (Index < 0 || Index >= class'APCatalog'.default.PickupCount || PickupIncluded[Index].bSet)
        return false;
    PickupIncluded[Index].bSet = true;
    return true;
}

function bool SendServerCommand(string Text)
{
    local int I;
    if (Left(Text, 1) != "!" || Len(Text) > 400)
    { Chat("Use an AP !command of at most 400 characters."); return false; }
    for (I = 0; I < Len(Text); I++)
        if (Asc(Mid(Text, I, 1)) < 32 || Asc(Mid(Text, I, 1)) == 127)
        { Chat("AP commands cannot contain control characters."); return false; }
    if (Client == None || Client.bFailed || !Client.bAuthenticated || Client.Bridge == None)
    { Chat("Connect to the AP server before sending commands."); return false; }
    if (!Client.Bridge.SendServerCommand(Text))
    { Chat("AP command was not sent; check the connection and try again."); return false; }
    return true;
}

function string CompletionName(int Index, bool bLocation)
{
    local int MapIndex, Milestone, I;
    local string Prefix;
    if (!bLocation)
    {
        if (Index < 82)
        {
            if (Selected[Index].bSet) return class'APCatalog'.default.Maps[Index] $ " Unlock";
        }
        else if (Index < 91) return class'APCatalog'.default.WeaponNames[Index - 82] $ " Unlock";
        else if (Index == 91) return "Health Refill";
        else if (Index == 92) return "Armor Refill";
        else if (Index < 102) return class'APCatalog'.default.AmmoFillerNames[Index - 93];
        else if (PickupUnlockMode == 1 && Index < 110)
            return class'APCatalog'.default.PickupFamilyNames[Index - 102] $ " Unlock";
        else if (PickupUnlockMode == 2 && Index < 134)
            return class'APCatalog'.default.PickupTypeNames[Index - 102];
        return "";
    }
    if (!DecodeCheck(Index, MapIndex, Milestone)) return "";
    Prefix = class'APCatalog'.default.Maps[MapIndex] $ " - ";
    if (Milestone < 0) return Prefix $ "Pickup " $ class'APCatalog'.static.PickupLabel(Index - 5000);
    if (Milestone == 0) return Prefix $ "Win";
    if (MapIndex < 37 || Index >= 10000) return Prefix $ "Frag Milestone " $ Milestone;
    if (class'APCatalog'.default.MapMode[MapIndex] == 1) return Prefix $ "Capture " $ Milestone;
    if (class'APCatalog'.default.MapMode[MapIndex] == 2) return Prefix $ "Score " $ (Milestone * 25);
    for (I = 0; I < class'APCatalog'.default.ObjectiveCount; I++)
        if (class'APCatalog'.static.ObjectiveMap(I) == MapIndex &&
            class'APCatalog'.static.ObjectiveStep(I) == Milestone)
            return Prefix $ "Objective " $ class'APCatalog'.static.ObjectiveLabel(I);
    return "";
}

function string CompleteHint(string Input, out int LastIndex)
{
    local bool bLocation;
    local int I, N, Limit;
    local string Prefix, Query, Candidate;
    if (Input ~= "!hint" || Left(Input, 6) ~= "!hint ")
    {
        Prefix = "!hint "; Query = Mid(Input, 6); Limit = 102;
        if (PickupUnlockMode == 1) Limit = 110;
        else if (PickupUnlockMode == 2) Limit = 134;
    }
    else if (Input ~= "!hint_location" || Left(Input, 15) ~= "!hint_location ")
    { Prefix = "!hint_location "; Query = Mid(Input, 15); Limit = 15000; bLocation = true; }
    else return CompleteServerCommand(Input, LastIndex);
    if (!bReady) return Input;
    for (N = 1; N <= Limit; N++)
    {
        I = (Max(-1, LastIndex) + N) % Limit;
        Candidate = CompletionName(I, bLocation);
        if (Candidate != "" && InStr(Caps(Candidate), Caps(Query)) >= 0)
        { LastIndex = I; return Prefix $ Candidate; }
    }
    return Input;
}

function string ServerCommandName(int Index)
{
    switch (Index)
    {
        case 0: return "!admin";
        case 1: return "!alias";
        case 2: return "!checked";
        case 3: return "!collect";
        case 4: return "!countdown";
        case 5: return "!getitem";
        case 6: return "!help";
        case 7: return "!hint";
        case 8: return "!hint_location";
        case 9: return "!license";
        case 10: return "!missing";
        case 11: return "!options";
        case 12: return "!players";
        case 13: return "!release";
        case 14: return "!remaining";
        case 15: return "!status";
    }
    return "";
}

function string CompleteServerCommand(string Input, out int LastIndex)
{
    local int I, N;
    local string Candidate;
    if (Left(Input, 1) != "!" || InStr(Input, " ") >= 0) return Input;
    for (N = 1; N <= 16; N++)
    {
        I = (Max(-1, LastIndex) + N) % 16;
        Candidate = ServerCommandName(I);
        if (Candidate != Input && Left(Candidate, Len(Input)) ~= Input)
        { LastIndex = I; return Candidate; }
    }
    return Input;
}

function string MutateCompletionName(int Index)
{
    if (Index >= 19 && Index < 101)
    {
        if (CanEnterMap(Index - 19))
            return "mutate ap start " $ class'APCatalog'.default.Maps[Index - 19];
        return "";
    }
    switch (Index)
    {
        case 0: return "mutate ";
        case 1: return "mutate ap ";
        case 2: return "mutate ap allrespawns";
        case 3: return "mutate ap connect";
        case 4: return "mutate ap disconnect";
        case 5: return "mutate ap host ";
        case 6: return "mutate ap maps";
        case 7: return "mutate ap minnotify";
        case 8: return "mutate ap password ";
        case 9: return "mutate ap pickupboxes";
        case 10: return "mutate ap port ";
        case 11: return "mutate ap progressionsound";
        case 12: return "mutate ap respawntimers";
        case 13: return "mutate ap say ";
        case 14: return "mutate ap skillspread";
        case 15: return "mutate ap slot ";
        case 16: return "mutate ap start ";
        case 17: return "mutate ap status";
        case 18: return "mutate ap timerthroughwalls";
    }
    return "";
}

function string CompleteMutate(string Input, out int LastIndex)
{
    local int I, N, Limit;
    local string Candidate;
    if (Input == "" || !(Left("mutate", Len(Input)) ~= Input || Left(Input, 6) ~= "mutate"))
        return Input;
    Limit = 19;
    if (Left(Input, 16) ~= "mutate ap start ") Limit += 82;
    for (N = 1; N <= Limit; N++)
    {
        I = (Max(-1, LastIndex) + N) % Limit;
        Candidate = MutateCompletionName(I);
        if (Candidate != "" && Candidate != Input && Left(Candidate, Len(Input)) ~= Input)
        { LastIndex = I; return Candidate; }
    }
    return Input;
}

defaultproperties
{
    Host="localhost"
    APPort=38281
    MinRespawnTimer=20
    bTimerThroughWalls=True
    bAutoConnect=True
    CurrentMap=-1
    bAlwaysTick=True
    FragIncrement=5
    MatchFragLimit=20
    BotSkill=2
    BotSkillSpread=0
    bProgressionSound=True
    bShowPickupBoxes=True
    bShowRespawnTimers=True
    bShowAllRespawns=False
    BotCount=3
}
