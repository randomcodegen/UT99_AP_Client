class APMarkerVisualGame extends APDeathMatch;

var int Frame;

function bool NeedPlayers() { return false; }

function PostBeginPlay()
{
    Super.PostBeginPlay();
    AP.bAutoConnect = false;
    AP.Progress.SelectSlot("AP marker visual fixture");
    AP.bPickupLocations = true;
    AP.bReady = true;
    AP.SetSelected(0, true);
    AP.SetSelected(1, true);
    AP.SetUnlocked(0, true);
    AP.PickupUnlockMode = 1;
    AP.AddPickupLocation(0);
    AP.FragIncrement = 1;
    AP.MatchFragLimit = 20;
    AP.Progress.MarkChecked(0);
    AP.Progress.MarkChecked(1);
    AP.Progress.MarkChecked(2);
    AP.Progress.MarkChecked(3);
    AP.Progress.MarkChecked(4);
    FragLimit = 20;
    AP.Client = Spawn(class'APClient');
    AP.Client.AP = AP;
    AP.Client.Bridge = new class'APNativeClient';
    AP.Client.bFailed = true;
    bAPStage = true;
    SetTimer(1, true);
}

function Timer()
{
    local PlayerPawn P;
    local APPickupMarker Marker;
    local vector Eye, Target;
    local Info Camera;
    local APConsoleEditBox Edit;
    local APMenuWindow MenuWindow;
    local APMenuClient MenuClient;
    foreach AllActors(class'PlayerPawn', P) if (P.Player != None) break;
    if (P == None) return;
    Frame++;
    if (Frame == 1)
    {
        AP.Mutate("ap minnotify 2", P);
        if (AP.MinNotify != 2) Log("AP VISUAL FAIL: minnotify command");
        AP.Mutate("ap minnotify garbage", P);
        if (AP.MinNotify != 2) Log("AP VISUAL FAIL: invalid minnotify accepted");
        AP.Mutate("ap_minnotify 0", P);
        if (AP.MinNotify != 2) Log("AP VISUAL FAIL: old minnotify command accepted");
        AP.Mutate("ap minnotify 0", P);
        if (AP.MinNotify != 0) Log("AP VISUAL FAIL: minnotify reset");
        class'APConsoleTextArea'.static.Install(P);
        MenuWindow = APMenuWindow(WindowConsole(P.Player.Console).Root.CreateWindow(
            class'APMenuWindow', 70, 15, 500, 450));
        if (MenuWindow != None) MenuClient = APMenuClient(MenuWindow.ClientArea);
        if (MenuClient == None) Log("AP VISUAL FAIL: arena overview missing");
        else
        {
            MenuClient.Tick(0);
            if (MenuClient.MapList.Items.Count() != 2 ||
                MenuClient.MapRow(0).DisplayName != "DM-Oblivion   5/21 (22)   Won" ||
                MenuClient.MapRow(1).DisplayName != "DM-Stalwart   0/0 (21)   Locked")
                Log("AP VISUAL FAIL: arena check overview");
            MenuClient.AP = None;
            MenuClient.Tick(0);
            if (MenuClient.AP != AP || MenuClient.MapList.Items.Count() != 2 ||
                MenuClient.MapRow(0).DisplayName != "DM-Oblivion   5/21 (22)   Won")
                Log("AP VISUAL FAIL: arena menu did not rebind after map travel");
            MenuClient.MapList.SetSelectedItem(MenuClient.MapRow(1));
            MenuClient.Tick(0);
            if (!MenuClient.PlayButton.bDisabled) Log("AP VISUAL FAIL: locked arena playable");
            AP.SetUnlocked(1, true);
            MenuClient.NextMapRefresh = 0;
            MenuClient.Tick(0);
            if (MenuClient.PlayButton.bDisabled || MenuClient.MapList.SelectedItem != MenuClient.MapRow(1) ||
                MenuClient.MapRow(1).DisplayName != "DM-Stalwart   0/21 (21)")
                Log("AP VISUAL FAIL: arena selection or unlock refresh");
            AP.SetUnlocked(1, false);
        }
        if (MenuWindow != None) MenuWindow.Close();
        AP.PickupUnlockMode = 0;
        AP.ResetPickupLocations();
        Edit = APConsoleEditBox(UWindowConsoleClientWindow(WindowConsole(P.Player.Console).ConsoleWindow.ClientArea).EditControl.EditBox);
        if (Edit == None) { Log("AP VISUAL FAIL: console edit hook"); ConsoleCommand("exit"); return; }
        Edit.SetValue("!h"); Edit.KeyDown(9, 0, 0); Edit.KeyDown(9, 0, 0);
        if (Edit.GetValue() != "!hint") Log("AP VISUAL FAIL: AP command tab cycling");
        Edit.SetValue("!rem"); Edit.KeyDown(9, 0, 0);
        if (Edit.GetValue() != "!remaining") Log("AP VISUAL FAIL: AP command completion");
        Edit.SetValue("!hint shoc"); Edit.KeyDown(9, 0, 0);
        if (Edit.GetValue() != "!hint Shock Rifle Unlock") Log("AP VISUAL FAIL: item tab completion");
        Edit.SetValue("!hint dm-"); Edit.KeyDown(9, 0, 0); Edit.KeyDown(9, 0, 0);
        if (Edit.GetValue() != "!hint DM-Stalwart Unlock") Log("AP VISUAL FAIL: tab cycling");
        Edit.SetValue("mut"); Edit.KeyDown(9, 0, 0);
        if (Edit.GetValue() != "mutate ") Log("AP VISUAL FAIL: mutate tab completion");
        Edit.SetValue("mutate ap st"); Edit.KeyDown(9, 0, 0); Edit.KeyDown(9, 0, 0);
        if (Edit.GetValue() != "mutate ap status") Log("AP VISUAL FAIL: AP command tab cycling");
        Edit.SetValue("mutate ap start dm-o"); Edit.KeyDown(9, 0, 0);
        if (Edit.GetValue() != "mutate ap start DM-Oblivion") Log("AP VISUAL FAIL: AP map tab completion");
        Edit.SetValue("!hint DM-Stalwart Unlock");
        Edit.KeyDown(13, 0, 0);
        if (Edit.GetValue() != "!hint DM-Stalwart Unlock") Log("AP VISUAL FAIL: offline input lost");
        Edit.SetValue("get UT99AP.APMutator MinNotify"); Edit.KeyDown(13, 0, 0);
        if (Edit.GetValue() != "") Log("AP VISUAL FAIL: stock command routing");
        AP.InitPickupMarkers();
        AP.RegisterHUDMutator();
        for (Marker = AP.FirstPickup; Marker != None; Marker = Marker.NextPickup)
        {
            Marker.ItemFlags = Marker.PickupIndex % 3;
            if (Marker.PickupIndex == 10)
            {
                Marker.Pickup.RespawnTime = 60;
                Marker.Pickup.GotoState('Sleeping');
            }
            if (Marker.PickupIndex == 9)
            {
                Marker.Pickup.RespawnTime = 10;
                Marker.Pickup.GotoState('Sleeping');
            }
        }
        P.SetPhysics(PHYS_None);
        P.bCollideWorld = false;
        P.SetCollision(false, false, false);
        P.PlayerReplicationInfo.bIsSpectator = true;
        P.bBehindView = false;
        // View three stock Shock Rifle/ammo spawns in DM-Oblivion.
        Eye = vect(0,240,-35);
        Target = vect(0,575,-65);
        P.SetLocation(Eye - vect(0,0,1) * P.EyeHeight);
        P.ClientSetRotation(rotator(Target - Eye));
        P.ViewRotation = rotator(Target - Eye);
        Camera = Spawn(class'APProgress',,,Eye,rotator(Target - Eye));
        P.ViewTarget = Camera;
        Log("AP VISUAL READY");
    }
    if (Frame == 3)
    {
        AP.MinNotify = 0;
        AP.ItemNotice("Health Refill", "UTPlayer2", 0);
        AP.ItemNotice("Shock Rifle Unlock", "UTPlayer2", 2);
        AP.ItemNotice("DM-Pressure Unlock", "UTPlayer1", 1, true);
        AP.NativeChat("{\"text\":\"Hint fixture\",\"parts\":[{\"text\":\"Hint: \"},{\"text\":\"DM-Pressure Unlock\",\"kind\":2,\"flags\":1},{\"text\":\" at \"},{\"text\":\"DM-Oblivion - Shock Rifle\",\"kind\":1},{\"text\":\" for \"},{\"text\":\"UTPlayer1\",\"kind\":3,\"self\":true}]}");
    }
    if (Frame == 4)
    {
        for (Marker = AP.FirstPickup; Marker != None; Marker = Marker.NextPickup)
            Log("AP VISUAL ORB " $ Marker.PickupIndex $ " flags " $ Marker.ItemFlags $ " visible " $ Marker.OrbVisible(P, P.ViewTarget.Location));
        P.ConsoleCommand("shot");
    }
    if (Frame == 5)
    {
        WindowConsole(P.Player.Console).bQuickKeyEnable = true;
        WindowConsole(P.Player.Console).LaunchUWindow();
        WindowConsole(P.Player.Console).ShowConsole();
        WindowConsole(P.Player.Console).ConsoleWindow.SetSize(280, 310);
        Edit = APConsoleEditBox(UWindowConsoleClientWindow(WindowConsole(P.Player.Console).ConsoleWindow.ClientArea).EditControl.EditBox);
        Edit.SetValue("!hint_location oblivion - win"); Edit.KeyDown(9, 0, 0);
        if (Edit.GetValue() != "!hint_location DM-Oblivion - Win") Log("AP VISUAL FAIL: location tab completion");
    }
    if (Frame == 6)
    {
        class'APConsoleTextArea'.static.Install(P);
        if (APConsoleTextArea(UWindowConsoleClientWindow(WindowConsole(P.Player.Console).ConsoleWindow.ClientArea).TextArea) == None)
            Log("AP VISUAL FAIL: console colors not installed");
        P.ConsoleCommand("shot");
    }
    if (Frame == 8) ConsoleCommand("exit");
}
