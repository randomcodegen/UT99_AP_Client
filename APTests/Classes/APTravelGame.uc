class APTravelGame extends APDeathMatch;

function PostBeginPlay()
{
    Super.PostBeginPlay();
    Spawn(class'APTravelDriver');
}

function bool NeedPlayers() { return false; }
