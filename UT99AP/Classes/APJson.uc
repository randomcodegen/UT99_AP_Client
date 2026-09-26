// Small JSON reader
class APJson extends Object;

static function SkipSpace(string S, out int P)
{
    while (P < Len(S) && Asc(Mid(S, P, 1)) <= 32)
        P++;
}

static function bool Value(string S, out int P, out string V, optional int Depth)
{
    local int Start, Code;
    local string C, EndChar, Part;
    V = "";
    if (Depth > 32) return false;
    SkipSpace(S, P);
    Start = P;
    C = Mid(S, P++, 1);
    if (C == "\"")
    {
        while (P < Len(S))
        {
            C = Mid(S, P++, 1);
            if (C == "\"") { V = Mid(S, Start, P - Start); return true; }
            if (Asc(C) < 32) return false;
            if (C == "\\")
            {
                C = Mid(S, P++, 1);
                if (C == "u")
                {
                    for (Code = 0; Code < 4; Code++)
                        if (HexDigit(Mid(S, P++, 1)) < 0) return false;
                }
                else if (InStr("\"\\/bfnrt", C) < 0 || C == "") return false;
            }
        }
        return false;
    }
    if (C == "{" || C == "[")
    {
        if (C == "{") EndChar = "}"; else EndChar = "]";
        SkipSpace(S, P);
        if (Mid(S, P, 1) != EndChar)
            while (true)
            {
                if (!Value(S, P, Part, Depth + 1)) return false;
                if (EndChar == "}")
                {
                    if (Left(Part, 1) != "\"") return false;
                    SkipSpace(S, P);
                    if (Mid(S, P++, 1) != ":") return false;
                    if (!Value(S, P, Part, Depth + 1)) return false;
                }
                SkipSpace(S, P);
                if (Mid(S, P, 1) == EndChar) break;
                if (Mid(S, P++, 1) != ",") return false;
            }
        P++;
    }
    else
    {
        while (P < Len(S) && InStr(",]} " $ Chr(9) $ Chr(10) $ Chr(13), Mid(S, P, 1)) < 0)
            P++;
        Part = Mid(S, Start, P - Start);
        if (Part != "true" && Part != "false" && Part != "null")
        {
            if (InStr("-0123456789", C) < 0 || C == "") return false;
            for (Code = 0; Code < Len(Part); Code++)
                if (InStr("0123456789.eE+-", Mid(Part, Code, 1)) < 0) return false;
        }
    }
    V = Mid(S, Start, P - Start);
    return V != "";
}

static function bool Next(string S, out int P, out string V)
{
    if (P == 0) P = 1;
    SkipSpace(S, P);
    if (Mid(S, P, 1) == ",") P++;
    SkipSpace(S, P);
    if (P >= Len(S) || Mid(S, P, 1) == "]") return false;
    return Value(S, P, V);
}

static function string Get(string S, string Key)
{
    local int P;
    local string K, V;
    if (Left(S, 1) != "{") return "";
    P = 1;
    while (Value(S, P, K))
    {
        SkipSpace(S, P);
        if (Mid(S, P++, 1) != ":" || !Value(S, P, V)) return "";
        if (Decode(K) == Key) return V;
        SkipSpace(S, P);
        if (Mid(S, P++, 1) != ",") break;
    }
    return "";
}

static function int HexDigit(string C)
{
    if (C == "") return -1;
    return InStr("0123456789ABCDEF", Caps(C));
}

static function string Decode(string S)
{
    local int P, I, N;
    local string C, R;
    if (Left(S, 1) != "\"") return S;
    for (P = 1; P < Len(S) - 1; P++)
    {
        C = Mid(S, P, 1);
        if (C == "\\")
        {
            C = Mid(S, ++P, 1);
            if (C == "u")
            {
                N = 0;
                for (I = 0; I < 4; I++) N = N * 16 + HexDigit(Mid(S, ++P, 1));
                C = Chr(N);
            }
            else if (C == "n") C = Chr(10);
            else if (C == "r") C = Chr(13);
            else if (C == "t") C = Chr(9);
            else if (C == "b") C = Chr(8);
            else if (C == "f") C = Chr(12);
        }
        R $= C;
    }
    return R;
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
