class APModeProbeAssault extends APAssault;
function PostBeginPlay()
{
    Super.PostBeginPlay();
    Spawn(class'APModeProbeDriver');
}
function bool NeedPlayers() { return false; }
