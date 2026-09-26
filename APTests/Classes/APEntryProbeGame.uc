class APEntryProbeGame extends GameInfo;

event PostBeginPlay()
{
    local APMutator AP;
    Super.PostBeginPlay();
    AP = Spawn(class'APMutator');
    if (AP != None)
    {
        AP.bAutoConnect = false;
        AP.bReady = true;
        AP.InventoryReady();
    }
    if (AP == None || AP.CurrentMap != -1 || AP.IsStage() || AP.CheckSummary == "")
        Log("AP ENTRY FAIL");
    else Log("AP ENTRY PASS");
    ConsoleCommand("exit");
}

function bool NeedPlayers() { return false; }
