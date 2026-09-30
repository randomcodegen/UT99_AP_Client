class APProgress extends Object config(UT99APProgress);

var config string Identity;
struct APFlag { var bool bSet; };
var APFlag Checked[15000];
var int Frags[82];
var config int NotifiedItemIndex;
var config int PendingHealth, PendingArmor;
var config int PendingWeaponAmmo[9];
var APFlag ActiveChecked[15000];
var int ActiveFrags[82];

static function APProgress GetSession()
{
    // the native package keeps this object alive across map travel
    if (class'APNativeClient'.default.ProgressCache == None)
        class'APNativeClient'.default.ProgressCache = new(None) class'APProgress';
    return APProgress(class'APNativeClient'.default.ProgressCache);
}

function bool IsChecked(int Index) { return ActiveChecked[Index].bSet; }
function bool IsPendingCheck(int Index) { return Checked[Index].bSet; }
function MarkChecked(int Index)
{
    ActiveChecked[Index].bSet = true;
    Checked[Index].bSet = true;
}
function ConfirmChecked(int Index)
{
    ActiveChecked[Index].bSet = true;
    Checked[Index].bSet = false;
}

function int GetFrag(int Index) { return ActiveFrags[Index]; }
function int GetPendingFrag(int Index) { return Frags[Index]; }
function SetLocalFrag(int Index, int Value)
{
    ActiveFrags[Index] = Value;
    Frags[Index] = Value;
}
function MergeFrag(int Index, int Value) { ActiveFrags[Index] = Max(ActiveFrags[Index], Value); }
function ConfirmFrag(int Index, int Value)
{
    ActiveFrags[Index] = Max(ActiveFrags[Index], Value);
    if (Frags[Index] > 0 && Value >= Frags[Index]) Frags[Index] = 0;
}

function SelectSlot(string NewIdentity)
{
    local int I;
    if (Identity != NewIdentity)
    {
        Identity = NewIdentity;
        NotifiedItemIndex = 0;
        PendingHealth = 0; PendingArmor = 0;
        for (I = 0; I < ArrayCount(PendingWeaponAmmo); I++) PendingWeaponAmmo[I] = 0;
        for (I = 0; I < ArrayCount(Checked); I++)
        {
            Checked[I].bSet = false;
            ActiveChecked[I].bSet = false;
        }
        for (I = 0; I < ArrayCount(Frags); I++)
        {
            Frags[I] = 0;
            ActiveFrags[I] = 0;
        }
        SaveConfig();
    }
}
