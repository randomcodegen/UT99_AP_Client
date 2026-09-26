// Color AP item rows.
class APConsoleTextArea extends UWindowConsoleTextAreaControl;

var APConsoleRow DrawingRow;

static function Install(PlayerPawn P, optional Canvas C)
{
    local WindowConsole WC;
    local UWindowConsoleClientWindow Client;
    local UWindowConsoleTextAreaControl Old;
    local APConsoleTextArea Area;
    local UWindowDynamicTextRow L;
    local bool bNewConsole;
    local int I;
    WC = WindowConsole(P.Player.Console);
    if (WC == None) return;
    if (!WC.bCreatedRoot)
    {
        WC.CreateRootWindow(C);
        bNewConsole = true;
    }
    if (WC.ConsoleWindow == None) return;
    Client = UWindowConsoleClientWindow(WC.ConsoleWindow.ClientArea);
    if (Client != None) class'APConsoleEditBox'.static.Install(Client);
    if (Client == None || Client.TextArea == None || APConsoleTextArea(Client.TextArea) != None) return;
    Old = Client.TextArea;
    Area = APConsoleTextArea(Client.CreateWindow(class'APConsoleTextArea', Old.WinLeft, Old.WinTop, Old.WinWidth, Old.WinHeight));
    for (L = UWindowDynamicTextRow(Old.List.Next); L != None; L = UWindowDynamicTextRow(L.Next))
    {
        Old.RemoveWrap(L);
        Area.AddText(L.Text);
    }
    Area.Font = Old.Font;
    Area.AbsoluteFont = Old.AbsoluteFont;
    Area.TextColor = Old.TextColor;
    Area.MaxLines = Old.MaxLines;
    Area.VertSB.Pos = Old.VertSB.Pos;
    Old.HideWindow();
    Client.TextArea = Area;
    if (bNewConsole)
    {
        // Vanilla setup copies only the first four messages, copy everything instead.
        Area.Clear();
        for (I = WC.NumLines; I >= 0; I--)
            Area.AddText(WC.GetMsgText((WC.TopLine + WC.MaxLines - I) % WC.MaxLines));
    }
}

function float DrawTextLine(Canvas C, UWindowDynamicTextRow L, float Y)
{
    local float H;
    DrawingRow = APConsoleRow(L);
    C.DrawColor = TextColor;
    H = Super.DrawTextLine(C, L, Y);
    DrawingRow = None;
    return H;
}

function UWindowDynamicTextRow AddText(string NewLine)
{
    local APConsoleRow Row;
    Row = APConsoleRow(Super.AddText(NewLine));
    // Vanilla reuses rows at the scrollback limit, make sure colors dont bleed into next message.
    if (Row != None) { Row.Message = None; Row.TextOffset = 0; }
    return Row;
}

function UWindowDynamicTextRow SplitRowAt(UWindowDynamicTextRow L, int SplitPos)
{
    local APConsoleRow Row, Next;
    local UWindowDynamicTextRow N;
    N = Super.SplitRowAt(L, SplitPos);
    Row = APConsoleRow(L); Next = APConsoleRow(N);
    if (Row != None && Next != None)
    {
        Next.Message = Row.Message;
        Next.TextOffset = Row.TextOffset + SplitPos;
    }
    return N;
}

function TextAreaClipText2(Canvas C, float X, float Y, coerce string S, optional bool bCheckHotkey)
{
    local int P, End, Offset;
    local float W, H;
    local color SavedColor;
    if (DrawingRow == None || DrawingRow.Message == None || S != DrawingRow.Text || bSelect)
    { Super.TextAreaClipText2(C, X, Y, S, bCheckHotkey); return; }
    SavedColor = C.DrawColor;
    Offset = DrawingRow.TextOffset;
    while (P < Len(S))
    {
        End = Min(Len(S), DrawingRow.Message.NextBoundary(Offset + P) - Offset);
        C.DrawColor = DrawingRow.Message.ColorAt(Offset + P);
        Super.TextAreaClipText2(C, X, Y, Mid(S, P, End - P), bCheckHotkey);
        TextAreaTextSize(C, Mid(S, P, End - P), W, H);
        X += W; P = End;
    }
    C.DrawColor = SavedColor;
}

defaultproperties
{
    RowClass=class'APConsoleRow'
}
