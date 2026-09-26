class APMenuClient extends UWindowDialogClientWindow;

var UWindowEditControl HostEdit, PortEdit, SlotEdit, PasswordEdit;
var UWindowSmallButton ConnectButton, DisconnectButton, PlayButton, FilterButton;
var UMenuMapListBox MapList;
var UMenuMapList MapRows[82];
var UWindowLabelControl StatusLabel, ProgressLabel, MapLabel, HelpLabel;
var APMutator AP;
var string LastMapState;
var float NextMapRefresh;
var bool bOnlyPlayable;

function UMenuMapList MapRow(int I) { return MapRows[I]; }

function UWindowEditControl AddEdit(string Label, string Value, int Y)
{
    local UWindowEditControl E;
    E = UWindowEditControl(CreateControl(class'UWindowEditControl', 16, Y, 455, 20));
    E.SetText(Label);
    E.EditBoxWidth = 330;
    E.SetValue(Value);
    E.SetMaxLength(128);
    return E;
}

function Created()
{
    Super.Created();
    foreach GetPlayerOwner().AllActors(class'APMutator', AP) break;
    if (AP == None && GetPlayerOwner().Level.NetMode == NM_Standalone)
        AP = GetPlayerOwner().Spawn(class'APMutator');
    HostEdit = AddEdit("Server / URL", class'APMutator'.default.Host, 16);
    PortEdit = AddEdit("Port", string(class'APMutator'.default.APPort), 44);
    PortEdit.SetNumericOnly(true);
    SlotEdit = AddEdit("Slot name", class'APMutator'.default.SlotName, 72);
    PasswordEdit = AddEdit("Password", "", 100);
    PasswordEdit.EditBox.Close();
    PasswordEdit.EditBox = APPasswordEdit(PasswordEdit.CreateWindow(class'APPasswordEdit', 0, 0, 330, 20));
    PasswordEdit.EditBox.NotifyOwner = PasswordEdit;
    PasswordEdit.SetValue(class'APMutator'.default.Password);
    ConnectButton = UWindowSmallButton(CreateControl(class'UWindowSmallButton', 16, 134, 120, 22));
    ConnectButton.SetText("Connect");
    DisconnectButton = UWindowSmallButton(CreateControl(class'UWindowSmallButton', 146, 134, 120, 22));
    DisconnectButton.SetText("Disconnect");
    StatusLabel = UWindowLabelControl(CreateControl(class'UWindowLabelControl', 16, 167, 455, 20));
    ProgressLabel = UWindowLabelControl(CreateControl(class'UWindowLabelControl', 16, 190, 455, 20));
    MapLabel = UWindowLabelControl(CreateControl(class'UWindowLabelControl', 16, 212, 455, 20));
    MapLabel.SetText("Seed arenas: checked / in logic (total)");
    FilterButton = UWindowSmallButton(CreateControl(class'UWindowSmallButton', 300, 208, 171, 22));
    FilterButton.SetText("Show playable + checks");
    MapList = UMenuMapListBox(CreateControl(class'UMenuMapListBox', 16, 233, 455, 143));
    PlayButton = UWindowSmallButton(CreateControl(class'UWindowSmallButton', 16, 381, 160, 24));
    PlayButton.SetText("Play selected arena");
    HelpLabel = UWindowLabelControl(CreateControl(class'UWindowLabelControl', 16, 408, 455, 20));
    HelpLabel.SetText("Enforcer and Impact Hammer are always available.");
    class'APConsoleTextArea'.static.Install(GetPlayerOwner());
}

function Tick(float Delta)
{
    local int I, WeaponCount, Previous, Collected, InLogic, Total;
    local string Snapshot, Label;
    if (AP == None || AP.bDeleteMe)
    {
        AP = None;
        foreach GetPlayerOwner().AllActors(class'APMutator', AP) break;
        if (LastMapState != "")
        {
            MapList.SelectedItem = None;
            MapList.Items.Clear();
            for (I = 0; I < 82; I++) MapRows[I] = None;
            LastMapState = "";
        }
        NextMapRefresh = 0;
    }
    if (AP == None)
    {
        StatusLabel.SetText("Connect to open the AP lobby.");
        ProgressLabel.SetText("");
        PlayButton.bDisabled = true;
        return;
    }
    StatusLabel.SetText(AP.Status);
    if (AP.bReady)
    {
        for (I = 0; I < 9; I++) if (AP.Weapons[I].bSet) WeaponCount++;
        ProgressLabel.SetText("Wins: " $ AP.WinCount() $ "/" $ AP.GoalRequired $ "    Weapons: " $ WeaponCount $ "/9");
        I = AP.StartingMap;
        if (AP.IsStage()) I = AP.CurrentMap;
        else if (MapList.SelectedItem != None) I = int(UMenuMapList(MapList.SelectedItem).MapName);
        if (I < 37)
            HelpLabel.SetText("Kill check every " $ AP.FragIncrement $ "; match target: " $ AP.MatchFragLimit $ ".");
        else if (class'APCatalog'.default.MapMode[I] == 1)
            HelpLabel.SetText("Captures: 1, 2, 3. Enemy frag check every " $ AP.FragIncrement $ ".");
        else if (class'APCatalog'.default.MapMode[I] == 2)
            HelpLabel.SetText("Team score: 25, 50, 75, 100. Enemy frag check every " $ AP.FragIncrement $ ".");
        else HelpLabel.SetText("Map objectives and an enemy frag check every " $ AP.FragIncrement $ ".");
    }
    else ProgressLabel.SetText("Waiting for connection and inventory sync.");
    if (!AP.bReady)
    {
        if (LastMapState != "")
        {
            MapList.SelectedItem = None;
            MapList.Items.Clear();
            for (I = 0; I < 82; I++) MapRows[I] = None;
            LastMapState = "";
        }
        PlayButton.bDisabled = true;
        return;
    }
    if (AP.Level.TimeSeconds >= NextMapRefresh)
    {
        AP.GetCheckCounts(Collected, InLogic, Total);
        for (I = 0; I < 82; I++)
            Snapshot $= string(AP.IsSelected(I) && (!bOnlyPlayable ||
                (AP.CanEnterMap(I) && AP.CollectedOnMap(I) < AP.InLogicOnMap(I))));
        if (Snapshot != LastMapState)
        {
            Previous = AP.StartingMap;
            if (AP.IsStage()) Previous = AP.CurrentMap;
            if (MapList.SelectedItem != None) Previous = int(UMenuMapList(MapList.SelectedItem).MapName);
            MapList.SelectedItem = None;
            MapList.Items.Clear();
            for (I = 0; I < 82; I++)
            {
                MapRows[I] = None;
                if (AP.IsSelected(I) && (!bOnlyPlayable ||
                    (AP.CanEnterMap(I) && AP.CollectedOnMap(I) < AP.InLogicOnMap(I))))
                {
                    MapRows[I] = UMenuMapList(MapList.Items.Append(class'UMenuMapList'));
                    MapRows[I].MapName = string(I);
                }
            }
            if (Previous >= 0 && Previous < 82 && MapRows[Previous] != None)
                MapList.SetSelectedItem(MapRows[Previous]);
            else MapList.SetSelectedItem(UMenuMapList(MapList.Items.Next));
            MapList.MakeSelectedVisible();
            LastMapState = Snapshot;
        }
        for (I = 0; I < 82; I++)
            if (MapRows[I] != None)
            {
                Label = class'APCatalog'.default.Maps[I] $ "   " $ AP.CollectedOnMap(I) $ "/" $ AP.InLogicOnMap(I) $ " (" $ AP.TotalOnMap(I) $ ")";
                if (AP.Progress.IsChecked(AP.CheckIndex(I, 0))) Label $= "   Won";
                else if (!AP.IsUnlocked(I)) Label $= "   Locked";
                else if (!AP.CanEnterMap(I)) Label $= "   Need " $ AP.StageWeaponsNeeded(I)
                    $ "/" $ AP.WeaponsOnMap(I) $ " weapons (have " $ AP.StageWeaponsHeld(I) $ ")";
                MapRows[I].DisplayName = Label;
            }
        NextMapRefresh = AP.Level.TimeSeconds + 1;
    }
    PlayButton.bDisabled = true;
    if (MapList.SelectedItem != None)
        PlayButton.bDisabled = !AP.CanEnterMap(int(UMenuMapList(MapList.SelectedItem).MapName));
}

function Notify(UWindowDialogControl C, byte E)
{
    Super.Notify(C, E);
    if (E != DE_Click) return;
    if (C == ConnectButton)
    {
        class'APMutator'.default.Host = HostEdit.GetValue();
        class'APMutator'.default.APPort = int(PortEdit.GetValue());
        class'APMutator'.default.SlotName = SlotEdit.GetValue();
        class'APMutator'.default.Password = PasswordEdit.GetValue();
        class'APMutator'.default.bAutoConnect = true;
        class'APMutator'.static.StaticSaveConfig();
        if (AP == None)
        {
            GetPlayerOwner().ClientTravel("DM-Oblivion?Game=UT99AP.APDeathMatch", TRAVEL_Absolute, false);
            Root.Console.CloseUWindow();
            ParentWindow.Close();
        }
        else
        {
            AP.Host = HostEdit.GetValue();
            AP.APPort = int(PortEdit.GetValue());
            AP.SlotName = SlotEdit.GetValue();
            AP.Password = PasswordEdit.GetValue();
            AP.Connect();
        }
    }
    else if (C == DisconnectButton && AP != None) AP.Disconnect();
    else if (C == FilterButton)
    {
        bOnlyPlayable = !bOnlyPlayable;
        if (bOnlyPlayable) FilterButton.SetText("Show all arenas");
        else FilterButton.SetText("Show playable + checks");
        NextMapRefresh = 0;
    }
    else if (C == PlayButton && !PlayButton.bDisabled)
    {
        AP.StartMap(int(UMenuMapList(MapList.SelectedItem).MapName), GetPlayerOwner());
        Root.Console.CloseUWindow();
        ParentWindow.Close();
    }
}

