class APNativeClient extends Object native;

var private int SessionId;

native final function string GetVersion();
native final function Connect(string URL, string Slot, string Password);
native final function Detach();
native final function Disconnect();
native final function bool PollEvent(out string Payload);
native final function SendLocationCheck(int LocationID);
native final function SendGoal();
native final function SendDeathLink();
native final function RequestSync();
native final function bool SendServerCommand(string Text);
native final function bool RequestFragSync();
native final function SetFrag(int MapIndex, int Value);
native final function ScoutLocation(int LocationID);
native final function bool ProjectPoint(Canvas C, vector Position, out float X, out float Y);
native final function DrawPickupMarker(Canvas C, vector Center, vector Extent, color OrbColor, bool ShowBox, bool ShowOrb);
