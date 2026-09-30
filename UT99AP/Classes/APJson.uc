// Small JSON reader
class APJson extends Object;

static function SkipSpace(string S, out int P)
{
    while (P < Len(S) && Asc(Mid(S, P, 1)) <= 32)
        P++;
}

static function bool Value(string S, out int P, out string V, optional int Depth)
{
    if (Depth > 32) return false;
    return class'APNativeClient'.static.ReadJsonValue(S, P, V);
}

static function bool Next(string S, out int P, out string V)
{
    return class'APNativeClient'.static.ReadJsonValue(S, P, V, true);
}

static function string Get(string S, string Key)
{
    return class'APNativeClient'.static.ReadJsonField(S, Key);
}

static function string Decode(string S)
{
    return class'APNativeClient'.static.ReadJsonString(S);
}

static function string Quote(string S)
{
    local int I, N;
    local string R, C, Hex;
    Hex = "0123456789abcdef";
    R = "\"";
    for (I = 0; I < Len(S); I++)
    {
        C = Mid(S, I, 1);
        N = Asc(C);
        if (C == "\"" || C == "\\") R $= "\\" $ C;
        else if (N < 32 || N > 126)
            R $= "\\u" $ Mid(Hex, (N >>> 12) & 15, 1) $ Mid(Hex, (N >>> 8) & 15, 1)
                        $ Mid(Hex, (N >>> 4) & 15, 1) $ Mid(Hex, N & 15, 1);
        else R $= C;
    }
    return R $ "\"";
}
