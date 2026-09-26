class APModeProbeDomination extends APDomination;
function PostBeginPlay()
{
    Super.PostBeginPlay();
    Spawn(class'APModeProbeDriver');
}
function bool NeedPlayers() { return false; }
