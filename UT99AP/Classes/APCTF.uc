class APCTF extends CTFGame;

var APMutator AP;
var bool bAPStage;

event InitGame(string Options, out string Error)
{
    Super.InitGame(Options, Error);
    bAPStage = GetIntOption(Options, "APStage", 0) == 1;
    AP = Spawn(class'APMutator');
    BaseMutator.AddMutator(AP);
    GoalTeamScore = 3;
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

function ScoreFlag(Pawn Scorer, CTFFlag theFlag)
{
    Super.ScoreFlag(Scorer, theFlag);
    if (AP != None) AP.TeamScoreProgress();
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
    GameName="Archipelago CTF"
    MapPrefix="CTF"
    MaxPlayers=1
    MaxSpectators=0
    bLocalLog=False
    bWorldLog=False
}
