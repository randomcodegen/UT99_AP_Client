class APMessageData extends Object;

var string Text;
struct TextRun { var int End; var color Tint; };
var TextRun Runs[32];
var int RunCount;

static function string Clean(string S)
{
    local int I, Code;
    local string Result, C;
    S = Left(S, 1024);
    for (I = 0; I < Len(S); I++)
    {
        C = Mid(S, I, 1); Code = Asc(C);
        if (Code < 32 || Code == 127) C = " ";
        Result $= C;
    }
    return Result;
}

function Add(string S, optional int Kind, optional int Flags, optional bool bSelf)
{
    local color C;
    S = Left(Clean(S), 1024 - Len(Text));
    if (S == "") return;
    Text $= S;
    C.R = 127; C.G = 127; C.B = 127;
    if (Kind == 1) { C.R = 0; C.G = 127; C.B = 63; } // AP location green: 00FF7F
    else if (Kind == 2) C = class'APItemMessage'.static.GetColor(Flags);
    else if (Kind == 3)
    {
        if (bSelf) { C.R = 119; C.G = 0; C.B = 119; }
        else { C.R = 125; C.G = 125; C.B = 105; }
    }
    if (RunCount > 0 && Runs[RunCount - 1].Tint == C) Runs[RunCount - 1].End = Len(Text);
    else if (RunCount < ArrayCount(Runs))
    {
        Runs[RunCount].End = Len(Text); Runs[RunCount].Tint = C; RunCount++;
    }
    else
    {
        // 32 runs cover normal AP text. Potentially TODO: Raise if breaking
        Runs[RunCount - 1].End = Len(Text);
        Runs[RunCount - 1].Tint.R = 127; Runs[RunCount - 1].Tint.G = 127; Runs[RunCount - 1].Tint.B = 127;
    }
}

// Match AP Text Client colors
function color ColorAt(int Offset)
{
    local int I;
    for (I = 0; I < RunCount; I++) if (Offset < Runs[I].End) return Runs[I].Tint;
    return class'APItemMessage'.default.DrawColor;
}

function int NextBoundary(int Offset)
{
    local int I;
    for (I = 0; I < RunCount; I++) if (Offset < Runs[I].End) return Runs[I].End;
    return Len(Text);
}

