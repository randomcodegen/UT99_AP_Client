class APSelfTestCommandlet extends Commandlet;

function int Main(string Args)
{
    local string V, S;
    local int P;
    local APMessageData M;
    local color C;
    M = new class'APMessageData';
    M.Add("Item "); M.Add("Unlock", 2, 1); M.Add(" at "); M.Add("DM-Pressure", 1);
    M.Add(" for "); M.Add("Self", 3, 0, true); M.Add(" from "); M.Add("Friend", 3);
    if (M.Text != "Item Unlock at DM-Pressure for Self from Friend") return 1;
    if (M.NextBoundary(0) != 5 || M.NextBoundary(5) != 11) return 1;
    C = M.ColorAt(0); if (C.R != 127 || C.G != 127 || C.B != 127) return 1;
    C = M.ColorAt(5); if (C.R != 87 || C.G != 76 || C.B != 119) return 1;
    C = M.ColorAt(15); if (C.R != 0 || C.G != 127 || C.B != 63) return 1;
    C = M.ColorAt(31); if (C.R != 119 || C.G != 0 || C.B != 119) return 1;
    C = M.ColorAt(41); if (C.R != 125 || C.G != 125 || C.B != 105) return 1;
    for (P = 0; P < 100; P++) M.Add("word", P % 4);
    if (M.RunCount != 32 || M.NextBoundary(Len(M.Text) - 1) != Len(M.Text)) return 1;
    for (P = 0; P < 8; P++)
    {
        if ((P & 1) != 0 && class'APItemMessage'.static.Rank(P) != 2) return 1;
        if ((P & 3) == 2 && class'APItemMessage'.static.Rank(P) != 1) return 1;
        if ((P & 3) == 0 && class'APItemMessage'.static.Rank(P) != 0) return 1;
    }
    P = 0;
    S = "[{\"cmd\":\"Connected\",\"nested\":{\"array\":[1,\"a\\\"b\",{}]},\"text\":\"Gr\\u00fc\\u00dfe\"}]";
    if (!class'APJson'.static.Value(S, P, V) || P != Len(S))
    { Log("FAIL: JSON nested packet"); return 1; }
    P = 0;
    if (!class'APJson'.static.Next(S, P, V)) return 1;
    if (class'APJson'.static.Decode(class'APJson'.static.Get(V, "text")) != ("Gr" $ Chr(252) $ Chr(223) $ "e"))
    { Log("FAIL: JSON unicode"); return 1; }
    S = "Quotes \" and slash \\ and " $ Chr(10) $ Chr(252);
    if (class'APJson'.static.Decode(class'APJson'.static.Quote(S)) != S)
    { Log("FAIL: JSON string roundtrip"); return 1; }
    P = 0;
    if (class'APJson'.static.Value("{\"a\":[1,]}", P, V))
    { Log("FAIL: accepted invalid JSON"); return 1; }
    P = 0;
    S = "[\"" $ Chr(252) $ "\",{\"x\":\"\\u65e5\\ud83d\\ude00\"},null,true,-1.5e2]";
    if (!class'APJson'.static.Next(S, P, V) || P != 4 ||
        class'APJson'.static.Decode(V) != Chr(252)) return 1;
    if (!class'APJson'.static.Next(S, P, V) ||
        class'APJson'.static.Decode(class'APJson'.static.Get(V, "x")) !=
        (Chr(26085) $ Chr(55357) $ Chr(56832))) return 1;
    if (!class'APJson'.static.Next(S, P, V) || V != "null") return 1;
    if (!class'APJson'.static.Next(S, P, V) || V != "true") return 1;
    if (!class'APJson'.static.Next(S, P, V) || V != "-1.5e2") return 1;
    if (class'APJson'.static.Next(S, P, V)) return 1;
    if (class'APJson'.static.Get("{\"a\":null}", "a") != "null" ||
        class'APJson'.static.Get("{\"a\":1}", "missing") != "") return 1;
    Log("AP SELFTEST PASS");
    return 0;
}

defaultproperties
{
    LogToStdout=True
    IsClient=False
    IsEditor=False
    IsServer=True
}
