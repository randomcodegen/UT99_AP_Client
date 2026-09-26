class APPickupMarker extends Actor;

var APMutator AP;
var Inventory Pickup;
var APPickupMarker NextPickup;
var int PickupIndex, ItemFlags;
var vector BoxExtent;
var bool bFamilyHidden;
var EDrawType SavedDrawType;

function RestorePickup()
{
    if (!bFamilyHidden || Pickup == None || Pickup.bDeleteMe) return;
    Pickup.DrawType = SavedDrawType;
    bFamilyHidden = false;
}

function UpdateFamilyVisibility()
{
    if (AP == None || Pickup == None || Pickup.bDeleteMe) return;
    if (AP.PickupUnlocked(PickupIndex)) { RestorePickup(); return; }
    if (!Pickup.IsInState('Pickup')) return;
    if (!bFamilyHidden)
    {
        SavedDrawType = Pickup.DrawType;
        bFamilyHidden = true;
    }
    Pickup.DrawType = DT_None;
}

function Tick(float Delta) { UpdateFamilyVisibility(); }

event Destroyed()
{
    RestorePickup();
    Super.Destroyed();
}

function int RespawnSeconds()
{
    if (AP == None || !AP.PickupUnlocked(PickupIndex) ||
        AP.Progress.IsChecked(5000 + PickupIndex) || Pickup == None ||
        Pickup.bDeleteMe || !Pickup.IsInState('Sleeping') ||
        Pickup.RespawnTime < Clamp(AP.MinRespawnTimer, 0, 600)) return 0;
    // UT's Sleep time includes the final spawn-effect delay
    return Max(1, int(Pickup.LatentFloat + 0.999));
}

function Touch(Actor Other)
{
    local PlayerPawn P;
    P = PlayerPawn(Other);
    if (AP == None || !AP.IsStage() || !AP.PickupUnlocked(PickupIndex) ||
        Level.Game.bGameEnded || P == None ||
        !AP.IsHuman(P) || P.Health <= 0) return;
    if (Pickup == None || Pickup.bDeleteMe || Pickup.bHidden || Pickup.Owner != None ||
        !Pickup.IsInState('Pickup')) return;
    if (!P.FastTrace(Location, P.Location)) return;
    AP.Check(5000 + PickupIndex);
}

function Timer()
{
    local Pawn P;
    // Retry touches from before connection or inventory sync
    if (AP == None || AP.Progress.IsChecked(5000 + PickupIndex)) return;
    foreach TouchingActors(class'Pawn', P) Touch(P);
}

function bool TimerVisible(PlayerPawn Viewer, vector Eye)
{
    local vector HitLocation, HitNormal;
    local Actor Hit;
    if (AP.bTimerThroughWalls) return true;
    Hit = Viewer.Trace(HitLocation, HitNormal, Location, Eye, true);
    return Hit == None || Hit == Pickup || Hit == Self;
}

function bool OrbVisible(PlayerPawn Viewer, vector Eye)
{
    local vector HitLocation, HitNormal, Orb;
    if (ItemFlags < 0) return false;
    Orb = Location + vect(0,0,1) * (BoxExtent.Z + 12);
    // Trace actors and BSP so closed moving objects hide the orb
    return Viewer.Trace(HitLocation, HitNormal, Orb, Eye, true) == None;
}

static function color ClassificationColor(int Flags)
{
    local color C;
    if ((Flags & 1) != 0) { C.R = 175; C.G = 153; C.B = 239; }
    else if ((Flags & 2) != 0) { C.R = 109; C.G = 139; C.B = 232; }
    else if ((Flags & 4) != 0) { C.R = 250; C.G = 128; C.B = 114; }
    else { C.R = 0; C.G = 238; C.B = 238; }
    return C;
}

defaultproperties
{
    ItemFlags=-1
    bHidden=True
    bCollideActors=True
    bBlockActors=False
    bBlockPlayers=False
    bProjTarget=False
    bGameRelevant=True
    RemoteRole=ROLE_None
}
