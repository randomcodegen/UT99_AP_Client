class APTravelGame extends APDeathMatch;

var int TestItemBurst;

event InitGame(string Options, out string Error)
{
    Super.InitGame(Options, Error);
    TestItemBurst = GetIntOption(Options, "APBurst", 0);
}

function PostBeginPlay()
{
    Super.PostBeginPlay();
    Spawn(class'APTravelDriver');
}

function bool NeedPlayers() { return false; }
