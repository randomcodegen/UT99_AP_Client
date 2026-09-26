class APItemMessage extends StringMessagePlus;

static function int Rank(int Flags)
{
    if ((Flags & 1) != 0) return 2;
    if ((Flags & 2) != 0) return 1;
    return 0;
}

static function string Label(int Flags)
{
    if ((Flags & 1) != 0) return "Progression";
    if ((Flags & 2) != 0) return "Useful";
    if ((Flags & 4) != 0) return "Trap";
    return "Filler";
}

static function color GetColor(optional int Switch,
    optional PlayerReplicationInfo RelatedPRI_1, optional PlayerReplicationInfo RelatedPRI_2)
{
    local color C;
    C = class'APPickupMarker'.static.ClassificationColor(Switch);
    // Tone down marker colors for HUD text to avoid washed-out pastels
    C.R = C.R / 2;
    C.G = C.G / 2;
    C.B = C.B / 2;
    return C;
}

static function RenderComplexMessage(Canvas C, out float XL, out float YL,
    optional string MessageString, optional int Switch,
    optional PlayerReplicationInfo RelatedPRI_1, optional PlayerReplicationInfo RelatedPRI_2,
    optional Object OptionalObject)
{
    local APMessageData Message;
    local int P, End, WordEnd;
    local float X, Y, LeftX, W, H;
    local color SavedColor;
    Message = APMessageData(OptionalObject);
    if (Message == None) { C.DrawText(MessageString, false); return; }
    SavedColor = C.DrawColor;
    LeftX = C.CurX; X = LeftX; Y = C.CurY;
    while (P < Len(Message.Text))
    {
        WordEnd = InStr(Mid(Message.Text, P), " ");
        if (WordEnd < 0) WordEnd = Len(Message.Text);
        else WordEnd += P + 1;
        C.TextSize(Mid(Message.Text, P, WordEnd - P), W, H);
        if (X > LeftX && X + W > C.ClipX) { X = LeftX; Y += YL; }
        while (P < WordEnd)
        {
            End = Min(WordEnd, Message.NextBoundary(P));
            C.DrawColor = Message.ColorAt(P);
            C.TextSize(Mid(Message.Text, P, End - P), W, H);
            C.SetPos(X, Y);
            C.DrawTextClipped(Mid(Message.Text, P, End - P));
            X += W;
            P = End;
        }
    }
    C.DrawColor = SavedColor;
}

defaultproperties
{
    bComplexString=True
    Lifetime=6
}
