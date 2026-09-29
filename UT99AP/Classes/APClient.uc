class APClient extends Info;

var APMutator AP;
var string SeedName;
var int ItemIndex;
var int LocalSlot;
var bool bAuthenticated, bHaveItems, bGoalSent, bFragsSynced;
var float AuthAge;
var APNativeClient Bridge;
var bool bFailed;
var bool bPickupsScouted;
var string Transport;
var string Players;
var string PendingItems;
var int PendingItemPos, PendingItemIndex;
var bool bUnlockChanged, bProgressDirty;
var float SaveAge;

function ConnectTo(string URL)
{
    Bridge = new class'APNativeClient';
    Bridge.Connect(URL, AP.SlotName, AP.Password);
}

event Destroyed()
{
    if (bProgressDirty && AP != None && AP.Progress != None) AP.Progress.SaveConfig();
    if (Bridge != None) Bridge.Detach();
    Super.Destroyed();
}

function Fail(string Reason)
{
    bFailed = true;
    if (Bridge != None) Bridge.Disconnect();
    OnFailure(Reason);
}

function OnFailure(string Reason)
{
    if (AP == None) return;
    AP.bReady = false;
    AP.Status = Reason;
    Log("AP: " $ Reason);
}

event Tick(float Delta)
{
    local int I;
    local string Packet;
    if (bFailed || Bridge == None || AP == None) return;
    if (PendingItems != "") DrainItems();
    else
    {
        for (I = 0; I < 16 && Bridge.PollEvent(Packet); I++)
        {
            OnMessage(Packet);
            if (bFailed) return;
            if (PendingItems != "") break;
        }
    }
    if (bProgressDirty)
    {
        SaveAge += Delta;
        if (SaveAge >= 1)
        {
            AP.Progress.SaveConfig();
            bProgressDirty = false;
            SaveAge = 0;
        }
    }
    AuthAge += Delta;
    if (AuthAge > 30 && PendingItems == "" && (!bHaveItems || !bFragsSynced) && !bFailed)
        Fail("AP synchronization timed out");
}

function OnMessage(string S)
{
    local string Packet, Command, V;
    local int P, EndPos;
    if (Left(S, 1) != "[" || !class'APJson'.static.Value(S, EndPos, V))
    { Fail("Invalid AP JSON message"); return; }
    class'APJson'.static.SkipSpace(S, EndPos);
    if (EndPos != Len(S)) { Fail("Trailing data in AP message"); return; }
    while (class'APJson'.static.Next(S, P, Packet))
    {
        if (bFailed) return;
        Command = class'APJson'.static.Decode(class'APJson'.static.Get(Packet, "cmd"));
        if (Command == "RoomInfo")
        {
            SeedName = class'APJson'.static.Decode(class'APJson'.static.Get(Packet, "seed_name"));
        }
        else if (Command == "NativeTransport")
        {
            V = class'APJson'.static.Decode(class'APJson'.static.Get(Packet, "url"));
            if (Left(V, 6) ~= "wss://") Transport = "TLS";
            else Transport = "ws";
            AP.Status = "Connected via " $ Transport $ "; authenticating";
            Log("AP: " $ AP.Status);
        }
        else if (Command == "NativeFallback")
        {
            AuthAge = 0;
            AP.Status = "TLS failed; trying ws://";
            Log("AP: " $ AP.Status);
        }
        else if (Command == "NativeDisconnected")
        {
            PendingItems = "";
            if (AP.bReady) AuthAge = 0;
            AP.bReady = false;
            bAuthenticated = false;
            bHaveItems = false;
            bFragsSynced = false;
            bGoalSent = false;
            AP.Status = "Reconnecting: " $ class'APJson'.static.Decode(class'APJson'.static.Get(Packet, "reason"));
        }
        else if (Command == "NativeFatal")
            Fail(class'APJson'.static.Decode(class'APJson'.static.Get(Packet, "reason")));
        else if (Command == "ConnectionRefused")
        {
            AP.bAutoConnect = false;
            Fail("Connection refused: " $ class'APJson'.static.Get(Packet, "errors"));
        }
        else if (Command == "Connected") ConnectedPacket(Packet);
        else if (Command == "ReceivedItems" && bAuthenticated) ItemsPacket(Packet);
        else if (Command == "NativeFrags" && bAuthenticated) FragsPacket(Packet);
        else if (Command == "NativeFragStored" && bAuthenticated) FragStoredPacket(Packet);
        else if (Command == "NativeChat" && bAuthenticated)
            AP.NativeChat(Packet);
        else if (Command == "NativeDeathLink" && bAuthenticated && AP.bReady)
            AP.ReceiveDeathLink(class'APJson'.static.Decode(class'APJson'.static.Get(Packet, "source")),
                class'APJson'.static.Decode(class'APJson'.static.Get(Packet, "cause")));
        else if (Command == "LocationInfo" && bAuthenticated) PickupInfoPacket(Packet);
        else if (Command == "RoomUpdate" && bAuthenticated)
        {
            V = class'APJson'.static.Get(Packet, "players");
            if (Left(V, 1) == "[") Players = V;
            CheckedPacket(class'APJson'.static.Get(Packet, "checked_locations"));
            if (AP.bReady) SendGoal();
        }
    }
}

function ConnectedPacket(string Packet)
{
    local string Data, Maps, Pickups, V, Identity;
    local int P, I, Count, Start, Goal, Increment, Limit, Schema, Skill, Bots, Mode, Percentage;
    Players = class'APJson'.static.Get(Packet, "players");
    LocalSlot = int(class'APJson'.static.Get(Packet, "slot"));
    Identity = SeedName $ ":" $ class'APJson'.static.Get(Packet, "team")
        $ ":" $ class'APJson'.static.Get(Packet, "slot");
    Data = class'APJson'.static.Get(Packet, "slot_data");
    Schema = int(class'APJson'.static.Get(Data, "schema_version"));
    if (Schema != 11)
    { AP.bAutoConnect = false; Fail("Incompatible UT99 world/client schema"); return; }
    if (class'APJson'.static.Get(Data, "pickup_catalog_version") != "2")
    { AP.bAutoConnect = false; Fail("Incompatible UT99 pickup catalog"); return; }
    V = class'APJson'.static.Get(Data, "pickup_unlock_mode");
    Mode = int(V);
    if (string(Mode) != V || Mode < 0 || Mode > 1)
    { Fail("Invalid pickup unlock mode"); return; }
    Mode++;
    V = class'APJson'.static.Get(Data, "weapon_logic_percentage");
    Percentage = int(V);
    if (string(Percentage) != V || Percentage < 0 || Percentage > 100)
    { Fail("Invalid weapon logic percentage"); return; }
    Start = int(class'APJson'.static.Get(Data, "starting_map"));
    Goal = int(class'APJson'.static.Get(Data, "goal_required"));
    Increment = int(class'APJson'.static.Get(Data, "frag_check_increment"));
    V = class'APJson'.static.Get(Data, "match_frag_limit");
    Limit = int(V);
    if (string(Limit) != V) { Fail("Invalid match frag limit"); return; }
    Skill = int(class'APJson'.static.Get(Data, "bot_skill"));
    Bots = int(class'APJson'.static.Get(Data, "bot_count"));
    if (Start < 0 || Start >= 82 || Goal < 1 || Increment < 1 || Increment > 25 ||
        Limit < 1 || Limit > 100 || Skill < 0 || Skill > 7 || Bots < 1 || Bots > 7)
    { Fail("Invalid UT99 slot settings"); return; }
    for (I = 0; I < 82; I++) AP.SetSelected(I, false);
    Maps = class'APJson'.static.Get(Data, "selected_maps");
    if (Left(Maps, 1) != "[") { Fail("Missing map pool"); return; }
    while (class'APJson'.static.Next(Maps, P, V))
    {
        I = int(V);
        if (string(I) != V || I < 0 || I >= 82) { Fail("Invalid map index"); return; }
        if (AP.IsSelected(I)) { Fail("Duplicate map index"); return; }
        AP.SetSelected(I, true);
        Count++;
    }
    if (Count < 2 || Goal > Count || !AP.IsSelected(Start) || SeedName == "")
    { Fail("Invalid map pool or goal"); return; }
    Pickups = class'APJson'.static.Get(Data, "pickup_locations");
    if (Left(Pickups, 1) != "[")
    { Fail("Missing pickup locations"); return; }
    if ((AP.PickupLocationSet != "" && AP.PickupLocationSet != Pickups) ||
        AP.PickupUnlockMode != Mode ||
        (AP.Progress.Identity != "" && AP.Progress.Identity != Identity)) AP.ClearPickupMarkers();
    AP.PickupLocationSet = Pickups;
    AP.ResetPickupLocations();
    P = 0;
    while (class'APJson'.static.Next(Pickups, P, V))
    {
        I = int(V) - 19996000;
        if (string(I + 19996000) != V || I < 0 || I >= class'APCatalog'.default.PickupCount)
        { Fail("Invalid pickup location"); return; }
        if (!AP.AddPickupLocation(I))
        { Fail("Duplicate pickup location"); return; }
        if (!AP.IsSelected(class'APCatalog'.static.PickupMap(I)))
        { Fail("Pickup location outside map pool"); return; }
    }
    AP.StartingMap = Start;
    AP.GoalRequired = Goal;
    AP.FragIncrement = Increment;
    AP.MatchFragLimit = Limit;
    AP.BotSkill = Skill;
    AP.BotCount = Bots;
    AP.WeaponLogicPercentage = Percentage;
    AP.bDeathLink = class'APJson'.static.Get(Data, "death_link") == "true";
    // Keep volumes on reconnect. Pickups might be respawning.
    if (!AP.bPickupLocations) AP.ClearPickupMarkers();
    AP.bPickupLocations = true;
    AP.PickupUnlockMode = Mode;
    bPickupsScouted = false;
    if (AP.Progress.Identity != "" && AP.Progress.Identity != Identity)
        AP.DisableStage();
    AP.Progress.SelectSlot(Identity);
    CheckedPacket(class'APJson'.static.Get(Packet, "checked_locations"));
    AP.bReady = false;
    PendingItems = "";
    bHaveItems = false;
    bFragsSynced = false;
    bGoalSent = false;
    AuthAge = 0;
    bAuthenticated = true;
    if (!Bridge.RequestFragSync()) { Fail("Could not request frag progress"); return; }
    AP.Status = "Connected; receiving inventory";
}

function ItemsPacket(string Packet)
{
    local string Items;
    local int Index, I;
    Index = int(class'APJson'.static.Get(Packet, "index"));
    if (Index == 0)
    {
        AP.bReady = false;
        bHaveItems = false;
        ItemIndex = 0;
        for (I = 0; I < 82; I++) AP.SetUnlocked(I, false);
        for (I = 0; I < 9; I++) AP.Weapons[I].bSet = false;
        for (I = 0; I < 8; I++) AP.PickupFamilies[I].bSet = false;
        for (I = 0; I < 32; I++) AP.PickupTypes[I].bSet = false;
    }
    else if (!bHaveItems || Index > ItemIndex)
    {
        AP.bReady = false;
        bHaveItems = false;
        AuthAge = 0;
        Bridge.RequestSync();
        return;
    }
    Items = class'APJson'.static.Get(Packet, "items");
    if (Left(Items, 1) != "[") { Fail("Invalid inventory packet"); return; }
    PendingItems = Items;
    PendingItemPos = 0;
    PendingItemIndex = Index;
    bUnlockChanged = false;
}

function DrainItems()
{
    local string Entry;
    local int I, ItemID, Flags;
    for (I = 0; I < 16 && class'APJson'.static.Next(PendingItems, PendingItemPos, Entry); I++)
    {
        if (PendingItemIndex >= ItemIndex)
        {
            ItemID = int(class'APJson'.static.Get(Entry, "item")) - 19990000;
            if (ItemID >= 0 && ItemID < 82)
            { AP.SetUnlocked(ItemID, true); bUnlockChanged = true; }
            else if (ItemID >= 100 && ItemID < 109)
            { AP.Weapons[ItemID - 100].bSet = true; bUnlockChanged = true; }
            else if (AP.PickupUnlockMode == 1 && ItemID >= 300 && ItemID < 308)
            { AP.PickupFamilies[ItemID - 300].bSet = true; bUnlockChanged = true; }
            else if (AP.PickupUnlockMode == 2 && ItemID >= 400 && ItemID < 432)
            { AP.PickupTypes[ItemID - 400].bSet = true; bUnlockChanged = true; }
            else if (ItemID != 201 && ItemID != 202 && (ItemID < 204 || ItemID > 212))
            { Fail("Unknown UT99 item ID; update the client"); return; }
            if (PendingItemIndex >= AP.Progress.NotifiedItemIndex)
            {
                if (ItemID == 201) AP.Progress.PendingHealth++;
                else if (ItemID == 202) AP.Progress.PendingArmor++;
                else if (ItemID >= 204 && ItemID <= 212) AP.Progress.PendingWeaponAmmo[ItemID - 204]++;
                // UT classes are fixed; AP may flag starting items as zero.
                Flags = 0;
                if (ItemID < 82 || (ItemID >= 300 && ItemID < 432) ||
                    (ItemID >= 100 && ItemID < 109 &&
                     (AP.PickupUnlockMode == 1 || AP.WeaponLogicPercentage > 0))) Flags = 1;
                else if (ItemID < 109) Flags = 2;
                if (class'APJson'.static.Get(Entry, "player") != "0" ||
                    class'APJson'.static.Get(Entry, "location") != "-2")
                    AP.ItemNotice(ItemName(ItemID), PlayerName(int(class'APJson'.static.Get(Entry, "player"))),
                        Flags, int(class'APJson'.static.Get(Entry, "player")) == LocalSlot,
                        class'APJson'.static.Decode(class'APJson'.static.Get(Entry, "location_name")));
                AP.Progress.NotifiedItemIndex = PendingItemIndex + 1;
                bProgressDirty = true;
            }
            ItemIndex++;
        }
        PendingItemIndex++;
    }
    class'APJson'.static.SkipSpace(PendingItems, PendingItemPos);
    if (Mid(PendingItems, PendingItemPos, 1) != "]") return;
    PendingItems = "";
    bHaveItems = true;
    TryReady();
}

function FragsPacket(string Packet)
{
    local int P, I, Value;
    local string Values, V;
    Values = class'APJson'.static.Get(Packet, "values");
    if (Left(Values, 1) != "[") { Fail("Invalid frag progress"); return; }
    while (class'APJson'.static.Next(Values, P, V))
    {
        Value = int(V);
        if (I >= 82 || string(Value) != V || Value < 0 || Value > 100)
        { Fail("Invalid frag progress"); return; }
        AP.Progress.ConfirmFrag(I, Min(Value, AP.MatchFragLimit));
        I++;
    }
    if (I != 82) { Fail("Invalid frag progress"); return; }
    bFragsSynced = true;
    TryReady();
}

function FragStoredPacket(string Packet)
{
    local int MapIndex, Value;
    local string V;
    V = class'APJson'.static.Get(Packet, "map");
    MapIndex = int(V);
    if (string(MapIndex) != V || MapIndex < 0 || MapIndex >= 82)
    { Fail("Invalid frag progress confirmation"); return; }
    V = class'APJson'.static.Get(Packet, "value");
    Value = int(V);
    if (string(Value) != V || Value < 0 || Value > 100)
    { Fail("Invalid frag progress confirmation"); return; }
    AP.Progress.ConfirmFrag(MapIndex, Min(Value, AP.MatchFragLimit));
}

function TryReady()
{
    local int I;
    if (!bHaveItems || !bFragsSynced) return;
    if (AP.bReady)
    {
        if (bUnlockChanged) AP.InventoryReady();
        else AP.ApplyFiller();
        return;
    }
    for (I = 0; I < 82; I++)
        if (AP.Progress.GetPendingFrag(I) > 0) Bridge.SetFrag(I, AP.Progress.GetPendingFrag(I));
    AP.Progress.SaveConfig();
    bProgressDirty = false;
    SaveAge = 0;
    AP.bReady = true;
    AP.Status = "Connected (" $ Transport $ ") to " $ SeedName;
    AP.InventoryReady();
    ScoutPickups();
    SendChecks();
    SendGoal();
}

function SendFrag(int MapIndex, int Value)
{
    if (bAuthenticated && bFragsSynced) Bridge.SetFrag(MapIndex, Value);
}

function CheckedPacket(string Checks)
{
    local int P, I, MapIndex, Milestone;
    local string V;
    while (class'APJson'.static.Next(Checks, P, V))
    {
        I = int(V) - 19991000;
        if (AP.DecodeCheck(I, MapIndex, Milestone))
        {
            AP.Progress.ConfirmChecked(I);
            if (Milestone > 0 && (MapIndex < 37 || I >= 10000))
            {
                AP.Progress.MergeFrag(MapIndex, Milestone * AP.FragIncrement);
                SendFrag(MapIndex, AP.Progress.GetFrag(MapIndex));
            }
        }
    }
}

function SendChecks()
{
    local int I, MapIndex, Milestone;
    if (!AP.bReady) return;
    for (I = 0; I < 15000; I++)
        if (AP.Progress.IsPendingCheck(I) && AP.DecodeCheck(I, MapIndex, Milestone))
            Bridge.SendLocationCheck(19991000 + I);
}

function SendGoal()
{
    if (AP.bReady && !bGoalSent && AP.WinCount() >= AP.GoalRequired)
    {
        bGoalSent = true;
        Bridge.SendGoal();
    }
}

function string ItemName(int ID)
{
    if (ID >= 0 && ID < 82) return class'APCatalog'.default.Maps[ID] $ " Unlock";
    if (ID >= 100 && ID < 109) return class'APCatalog'.default.WeaponNames[ID - 100] $ " Unlock";
    if (ID >= 300 && ID < 308) return class'APCatalog'.default.PickupFamilyNames[ID - 300] $ " Unlock";
    if (ID >= 400 && ID < 432) return class'APCatalog'.default.PickupTypeNames[ID - 400];
    if (ID == 201) return "Health Refill";
    if (ID == 202) return "Armor Refill";
    if (ID >= 204 && ID <= 212) return class'APCatalog'.default.AmmoFillerNames[ID - 204];
    return "";
}

function string PlayerName(int Slot)
{
    local int P;
    local string Entry, Alias;
    if (Slot == 0) return "Server";
    while (class'APJson'.static.Next(Players, P, Entry))
        if (int(class'APJson'.static.Get(Entry, "slot")) == Slot)
        {
            Alias = class'APJson'.static.Decode(class'APJson'.static.Get(Entry, "alias"));
            if (Alias == "") Alias = class'APJson'.static.Decode(class'APJson'.static.Get(Entry, "name"));
            if (Alias != "") return Alias;
        }
    return "Player " $ Slot;
}

function ScoutPickups()
{
    local APPickupMarker Marker;
    if (!AP.bReady || bPickupsScouted || !AP.bPickupLocations) return;
    for (Marker = AP.FirstPickup; Marker != None; Marker = Marker.NextPickup)
    {
        Marker.ItemFlags = -1;
        if (!AP.Progress.IsChecked(5000 + Marker.PickupIndex))
            Bridge.ScoutLocation(19996000 + Marker.PickupIndex);
    }
    // No lobby volumes; map travel creates a client that scouts the arena.
    bPickupsScouted = true;
}

function PickupInfoPacket(string Packet)
{
    local int P, I, Flags;
    local string Items, Entry, V;
    local APPickupMarker Marker;
    Items = class'APJson'.static.Get(Packet, "locations");
    if (Left(Items, 1) != "[") { Fail("Invalid pickup scouting response"); return; }
    while (class'APJson'.static.Next(Items, P, Entry))
    {
        V = class'APJson'.static.Get(Entry, "location");
        I = int(V);
        if (string(I) != V) { Fail("Invalid scouted location ID"); return; }
        I -= 19996000;
        if (I < 0 || I >= class'APCatalog'.default.PickupCount) continue;
        V = class'APJson'.static.Get(Entry, "flags");
        Flags = int(V);
        if (string(Flags) != V || Flags < 0 || Flags > 7)
        { Fail("Invalid scouted item flags"); return; }
        for (Marker = AP.FirstPickup; Marker != None; Marker = Marker.NextPickup)
            if (Marker.PickupIndex == I) Marker.ItemFlags = Flags;
    }
}

defaultproperties
{
    bAlwaysTick=True
}
