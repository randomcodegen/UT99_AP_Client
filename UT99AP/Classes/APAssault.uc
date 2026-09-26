class APAssault extends Assault;

var APMutator AP;
var bool bAPStage;

event InitGame(string Options, out string Error)
{
    SavedTime = 0;
    bDefenseSet = false;
    Part = 1;
    Super.InitGame(Options, Error);
    bAPStage = GetIntOption(Options, "APStage", 0) == 1;
    AP = Spawn(class'APMutator');
    BaseMutator.AddMutator(AP);
    bDontRestart = true;
    bChangeLevels = false;
    bRatedGame = false;
    bTournament = false;
}

function PostBeginPlay()
{
    Super.PostBeginPlay();
    RemainingBots = 0;
}

function bool NeedPlayers()
{
    if (AP == None || !AP.IsStage()) return false;
    return Super.NeedPlayers();
}

function ModifyBehaviour(Bot NewBot)
{
    if (AP != None) AP.AdjustBot(NewBot);
}

function RemoveFort(FortStandard F, Pawn Instigator)
{
    Super.RemoveFort(F, Instigator);
    if (AP != None) AP.ObjectiveFort(F.Name);
}

function Timer()
{
    if (AP != None && AP.IsStage() && !bGameEnded) Super.Timer();
}

function RestartGame()
{
    if (bAPStage && bGameEnded && EndTime <= Level.TimeSeconds)
        Level.ServerTravel("?Restart", false);
}

defaultproperties
{
    GameName="Archipelago Assault"
    MapPrefix="AS"
    MaxPlayers=1
    MaxSpectators=0
    bLocalLog=False
    bWorldLog=False
}
