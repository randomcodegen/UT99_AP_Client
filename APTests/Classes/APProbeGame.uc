class APProbeGame extends APDeathMatch;

function PostBeginPlay()
{
    Super.PostBeginPlay();
    Spawn(class'APProbeDriver');
}

function bool NeedPlayers() { return false; }
