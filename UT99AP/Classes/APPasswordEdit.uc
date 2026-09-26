class APPasswordEdit extends UWindowEditBox;

function Paint(Canvas C, float X, float Y)
{
    local string Original;
    local int I;
    Original = Value;
    Value = "";
    for (I = 0; I < Len(Original); I++) Value $= "*";
    Super.Paint(C, X, Y);
    Value = Original;
}
