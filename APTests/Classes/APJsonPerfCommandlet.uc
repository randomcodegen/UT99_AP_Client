class APJsonPerfCommandlet extends Commandlet;

function int Main(string Args)
{
    local string S, V, Packet, Items, Entry, Checks, Data;
    local int I, P, EndPos;
    Items = "[";
    for (I = 0; I < 500; I++)
    {
        if (I > 0) Items $= ",";
        Items $= "{\"item\":19990201,\"player\":2,\"location\":19996000,\"flags\":0," $
            "\"location_name\":\"DM-Pressure - Pickup HealthVial " $ I $ "\"}";
    }
    Items $= "]";
    S = "[{\"cmd\":\"ReceivedItems\",\"index\":7,\"items\":" $ Items $ "}]";
    Log("AP PERF: validation begin");
    if (!class'APJson'.static.Value(S, EndPos, V) || EndPos != Len(S)) return 1;
    Log("AP PERF: command extraction begin");
    if (!class'APJson'.static.Next(S, P, Packet)) return 1;
    if (class'APJson'.static.Decode(class'APJson'.static.Get(Packet, "cmd")) != "ReceivedItems") return 1;
    if (class'APJson'.static.Get(Packet, "index") != "7") return 1;
    Items = class'APJson'.static.Get(Packet, "items");
    Log("AP PERF: item iteration begin");
    P = 0;
    I = 0;
    while (class'APJson'.static.Next(Items, P, Entry))
    {
        if (class'APJson'.static.Get(Entry, "item") != "19990201") return 1;
        if (class'APJson'.static.Get(Entry, "player") != "2") return 1;
        if (class'APJson'.static.Get(Entry, "location") != "19996000") return 1;
        V = class'APJson'.static.Decode(class'APJson'.static.Get(Entry, "location_name"));
        I++;
    }
    if (I != 500) return 1;
    Checks = "[";
    for (I = 0; I < 4000; I++)
    {
        if (I > 0) Checks $= ",";
        Checks $= string(19996000 + I);
    }
    Checks $= "]";
    S = "{\"checked_locations\":" $ Checks $ ",\"cmd\":\"Connected\",\"players\":[],\"slot\":1," $
        "\"slot_data\":{\"pickup_locations\":" $ Checks $ ",\"schema_version\":11},\"team\":0}";
    Log("AP PERF: reconnect extraction begin");
    for (I = 0; I < 10; I++)
    {
        if (class'APJson'.static.Get(S, "cmd") != "\"Connected\"") return 1;
        Data = class'APJson'.static.Get(S, "slot_data");
        if (class'APJson'.static.Get(Data, "schema_version") != "11") return 1;
    }
    P = 0;
    I = 0;
    while (class'APJson'.static.Next(Checks, P, V))
    {
        if (int(V) != 19996000 + I) return 1;
        I++;
    }
    if (I != 4000) return 1;
    Log("AP PERF PASS");
    return 0;
}

defaultproperties
{
    LogToStdout=True
    IsClient=False
    IsEditor=False
    IsServer=True
}
