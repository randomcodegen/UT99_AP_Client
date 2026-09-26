class APTestGame extends APDeathMatch;

function PostBeginPlay()
{
    Super.PostBeginPlay();
    Spawn(class'APTestDriver');
}

function bool NeedPlayers() { return false; }
