class APDomination extends Domination;

var APMutator AP;
var bool bAPStage;

event InitGame(string Options, out string Error)
{
    Super.InitGame(Options, Error);
    bAPStage = GetIntOption(Options, "APStage", 0) == 1;
    AP = Spawn(class'APMutator');
    BaseMutator.AddMutator(AP);
    GoalTeamScore = 100;
    TimeLimit = 0;
    RemainingTime = 0;
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

function Timer()
{
    if (AP == None || !AP.IsStage() || bGameEnded) return;
    Super.Timer();
    AP.TeamScoreProgress();
}

function RestartGame()
{
    if (bAPStage && bGameEnded && EndTime <= Level.TimeSeconds)
        Level.ServerTravel("?Restart", false);
}

defaultproperties
{
    GameName="Archipelago Domination"
    MapPrefix="DOM"
    MaxPlayers=1
    MaxSpectators=0
    bLocalLog=False
    bWorldLog=False
}
