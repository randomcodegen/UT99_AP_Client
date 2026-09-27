// Keep UE1 headers out of Session.cpp: the x86 version uses 4-byte packing and
// both versions define names that conflict with modern C++ libraries.
#include "Engine.h"
#include "UnRenDev.h"
#include "Session.h"

// Win32 UT uses unsigned short; Win64 UT uses wchar_t. Both carry UTF-16.
static_assert(sizeof(TCHAR) == sizeof(unsigned short), "Session expects UTF-16");

class UAPNativeClient : public UObject
{
public:
    INT SessionId;
    DECLARE_CLASS(UAPNativeClient, UObject, 0, UT99APNative)
    NO_DEFAULT_CONSTRUCTOR(UAPNativeClient)
    DECLARE_FUNCTION(execGetVersion)
    DECLARE_FUNCTION(execConnect)
    DECLARE_FUNCTION(execDetach)
    DECLARE_FUNCTION(execDisconnect)
    DECLARE_FUNCTION(execPollEvent)
    DECLARE_FUNCTION(execSendLocationCheck)
    DECLARE_FUNCTION(execSendGoal)
    DECLARE_FUNCTION(execSendDeathLink)
    DECLARE_FUNCTION(execRequestSync)
    DECLARE_FUNCTION(execSendServerCommand)
    DECLARE_FUNCTION(execRequestFragSync)
    DECLARE_FUNCTION(execSetFrag)
    DECLARE_FUNCTION(execScoutLocation)
    DECLARE_FUNCTION(execDrawPickupMarker)
    DECLARE_FUNCTION(execProjectPoint)
    void Destroy() override { SessionDetach(SessionId); SessionId = 0; Super::Destroy(); }
};

IMPLEMENT_PACKAGE(UT99APNative)
IMPLEMENT_CLASS(UAPNativeClient)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execGetVersion)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execConnect)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execDetach)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execDisconnect)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execPollEvent)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execSendLocationCheck)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execSendGoal)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execSendDeathLink)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execRequestSync)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execSendServerCommand)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execRequestFragSync)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execSetFrag)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execScoutLocation)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execDrawPickupMarker)
IMPLEMENT_FUNCTION(UAPNativeClient, -1, execProjectPoint)

void UAPNativeClient::execGetVersion(FFrame& Stack, RESULT_DECL)
{
    P_FINISH;
    *(FString*)Result = TEXT("UT99APNative 0.4.6");
}
void UAPNativeClient::execConnect(FFrame& Stack, RESULT_DECL) {
    P_GET_STR(URL); P_GET_STR(Slot); P_GET_STR(Password); P_FINISH;
    SessionId = SessionOpen(reinterpret_cast<const unsigned short*>(*URL),
                           reinterpret_cast<const unsigned short*>(*Slot),
                           reinterpret_cast<const unsigned short*>(*Password));
}
void UAPNativeClient::execDetach(FFrame& Stack, RESULT_DECL) {
    P_FINISH; SessionDetach(SessionId); SessionId = 0;
}
void UAPNativeClient::execDisconnect(FFrame& Stack, RESULT_DECL) {
    P_FINISH; SessionClose(SessionId); SessionId = 0;
}
void UAPNativeClient::execPollEvent(FFrame& Stack, RESULT_DECL) {
    P_GET_STR_REF(Payload); P_FINISH;
    const unsigned short* text = SessionPoll(SessionId);
    *Payload = text ? reinterpret_cast<const TCHAR*>(text) : TEXT("");
    *(UBOOL*)Result = text != nullptr;
}
void UAPNativeClient::execSendLocationCheck(FFrame& Stack, RESULT_DECL) {
    P_GET_INT(LocationID); P_FINISH; SessionCheck(SessionId, LocationID);
}
void UAPNativeClient::execSendGoal(FFrame& Stack, RESULT_DECL) { P_FINISH; SessionGoal(SessionId); }
void UAPNativeClient::execSendDeathLink(FFrame& Stack, RESULT_DECL) { P_FINISH; SessionDeath(SessionId); }
void UAPNativeClient::execRequestSync(FFrame& Stack, RESULT_DECL) { P_FINISH; SessionSync(SessionId); }
void UAPNativeClient::execSendServerCommand(FFrame& Stack, RESULT_DECL) {
    P_GET_STR(Text); P_FINISH;
    *(UBOOL*)Result = SessionSay(SessionId, reinterpret_cast<const unsigned short*>(*Text));
}
void UAPNativeClient::execRequestFragSync(FFrame& Stack, RESULT_DECL) {
    P_FINISH; *(UBOOL*)Result = SessionRequestFrags(SessionId);
}
void UAPNativeClient::execSetFrag(FFrame& Stack, RESULT_DECL) {
    P_GET_INT(MapIndex); P_GET_INT(Value); P_FINISH;
    SessionSetFrag(SessionId, MapIndex, Value);
}
void UAPNativeClient::execScoutLocation(FFrame& Stack, RESULT_DECL) {
    P_GET_INT(LocationID); P_FINISH; SessionScout(SessionId, LocationID);
}

void UAPNativeClient::execProjectPoint(FFrame& Stack, RESULT_DECL) {
    P_GET_OBJECT(UCanvas, Canvas); P_GET_VECTOR(Position);
    P_GET_FLOAT_REF(X); P_GET_FLOAT_REF(Y); P_FINISH;
    *(UBOOL*)Result = 0;
    if (!Canvas || !Canvas->Frame) return;
    FTransform projected;
    projected.Point = Position.TransformPointBy(Canvas->Frame->Coords);
    if (projected.Point.Z <= 1.f) return;
    projected.Project(Canvas->Frame);
    *X = projected.ScreenX; *Y = projected.ScreenY;
    *(UBOOL*)Result = *X >= 0 && *Y >= 0 && *X < Canvas->Frame->X && *Y < Canvas->Frame->Y;
}

// UnrealScript controls location status and visibility whereas this only draws
void UAPNativeClient::execDrawPickupMarker(FFrame& Stack, RESULT_DECL) {
    P_GET_OBJECT(UCanvas, Canvas);
    P_GET_VECTOR(Center); P_GET_VECTOR(Extent);
    P_GET_STRUCT(FColor, OrbColor); P_GET_UBOOL(ShowBox); P_GET_UBOOL(ShowOrb); P_FINISH;
    if (!Canvas || !Canvas->Frame || !Canvas->Viewport || !Canvas->Viewport->RenDev) return;
    URenderDevice* device = Canvas->Viewport->RenDev;
    FVector corners[8];
    for (INT i = 0; i < 8; ++i)
        corners[i] = Center + FVector((i & 1) ? Extent.X : -Extent.X,
                                     (i & 2) ? Extent.Y : -Extent.Y,
                                     (i & 4) ? Extent.Z : -Extent.Z);
    if (ShowBox)
        for (INT i = 0; i < 8; ++i)
            for (INT bit = 1; bit <= 4; bit <<= 1)
                if (!(i & bit))
                    device->Draw3DLine(Canvas->Frame, FPlane(0.45f, 0.45f, 0.45f, 1.f),
                                       LINE_None, corners[i], corners[i | bit]);
    if (!ShowOrb) return;
    FTransform projected;
    projected.Point = (Center + FVector(0, 0, Extent.Z + 12)).TransformPointBy(Canvas->Frame->Coords);
    if (projected.Point.Z <= 1.f) return;
    projected.Project(Canvas->Frame);
    const FLOAT x = projected.ScreenX, y = projected.ScreenY;
    const FLOAT radius = Clamp(6.f * projected.RZ, 2.f, 12.f);
    if (x + radius < 0 || y + radius < 0 || x - radius > Canvas->Frame->X || y - radius > Canvas->Frame->Y) return;
    // Draw a shaded circle
    for (INT row = -appFloor(radius); row <= appFloor(radius); ++row) {
        const FLOAT halfWidth = appSqrt(Max(0.f, radius * radius - FLOAT(row * row)));
        const FLOAT light = 0.65f + 0.35f * (1.f - Abs(FLOAT(row) / radius));
        device->Draw2DLine(Canvas->Frame,
            FPlane(OrbColor.R / 255.f * light, OrbColor.G / 255.f * light, OrbColor.B / 255.f * light, 1.f),
            LINE_None, FVector(x - halfWidth, y + row, 1.f), FVector(x + halfWidth, y + row, 1.f));
    }
}
