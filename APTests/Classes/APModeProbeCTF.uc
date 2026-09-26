class APModeProbeCTF extends APCTF;
function PostBeginPlay()
{
    Super.PostBeginPlay();
    Spawn(class'APModeProbeDriver');
}
function bool NeedPlayers() { return false; }
