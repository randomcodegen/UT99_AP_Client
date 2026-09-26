// Intercept AP commands and completion.
class APConsoleEditBox extends UWindowEditBox;

var string CompletionInput, LastCompletion;
var int CompletionIndex;

static function Install(UWindowConsoleClientWindow Client)
{
    local UWindowEditBox Old;
    local APConsoleEditBox Edit;
    Old = Client.EditControl.EditBox;
    if (APConsoleEditBox(Old) != None) return;
    Edit = APConsoleEditBox(Client.EditControl.CreateWindow(class'APConsoleEditBox', Old.WinLeft, Old.WinTop, Old.WinWidth, Old.WinHeight));
    Edit.NotifyOwner = Client.EditControl;
    Edit.Font = Old.Font; Edit.TextColor = Old.TextColor;
    Edit.MaxLength = Old.MaxLength; Edit.bSelectOnFocus = Old.bSelectOnFocus;
    Edit.bHistory = Old.bHistory; Edit.HistoryList = Old.HistoryList;
    Edit.CurrentHistory = Old.CurrentHistory;
    Edit.Value = Old.Value; Edit.CaretOffset = Old.CaretOffset;
    Old.HideWindow();
    Client.EditControl.EditBox = Edit;
}

function APMutator FindAP()
{
    local APMutator AP;
    local PlayerPawn P;
    P = GetPlayerOwner();
    if (P == None || P.Level.NetMode != NM_Standalone) return None;
    foreach P.AllActors(class'APMutator', AP) return AP;
    return None;
}

function KeyDown(int Key, float X, float Y)
{
    local APMutator AP;
    local string Completed;
    if (Key == 9 && (Left(Value, 1) == "!" ||
        (Value != "" && (Left("mutate", Len(Value)) ~= Value || Left(Value, 6) ~= "mutate"))))
    {
        AP = FindAP();
        if (AP == None) return;
        if (Value != LastCompletion) { CompletionInput = Value; CompletionIndex = -1; }
        if (Left(CompletionInput, 1) == "!")
            Completed = AP.CompleteHint(CompletionInput, CompletionIndex);
        else Completed = AP.CompleteMutate(CompletionInput, CompletionIndex);
        SetValue(Completed); CaretOffset = Len(Value); bAllSelected = false;
        LastCompletion = Value;
        return;
    }
    Super.KeyDown(Key, X, Y);
}

function Notify(byte E)
{
    local APMutator AP;
    local UWindowConsoleClientWindow Client;
    local UWindowEditBoxHistory H;
    local int I;
    if (E != DE_EnterPressed || Left(Value, 1) != "!") { Super.Notify(E); return; }
    AP = FindAP();
    if (AP == None) { Root.Console.Message(None, "AP: Start an Archipelago lobby first.", 'Console'); return; }
    if (!AP.SendServerCommand(Value)) return;
    Root.Console.Message(None, "> " $ Value, 'Console');
    Client = UWindowConsoleClientWindow(NotifyOwner.ParentWindow);
    if (Client != None)
    {
        H = HistoryList;
        for (I = 0; I < 32; I++)
        {
            if (H.Next == None) Client.History[I] = "";
            else { H = UWindowEditBoxHistory(H.Next); Client.History[I] = H.HistoryText; }
        }
        Client.SaveConfig();
    }
    Clear();
}
