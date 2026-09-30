#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdlib>
#include <cwchar>
#include <deque>
#include <mutex>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <json/json.h>
#include "Archipelago.h"
#include "Session.h"

namespace {
// APCpp has one process-wide session. Tokens stop stale Unreal objects
// from closing a new connection after map travel.
int currentId = 0;
int nextId = 0;
bool sessionActive = false;
std::string activeUrl, activeSlot, activePassword;
std::mutex queueMutex;
std::deque<std::string> events;
size_t queuedBytes = 0;
bool overflow = false;
std::string roomInfoPacket, transportPacket;
std::set<int64_t> pendingChecks;
std::set<int64_t> pendingScouts;
std::unique_ptr<AP_GetServerDataRequest> fragRequests[82];
int fragValues[82];
std::string fragPrefix;
bool fragSyncRequested = false;

std::string Utf8(const unsigned short* text) {
    auto wide = reinterpret_cast<const wchar_t*>(text);
    int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, nullptr, 0, nullptr, nullptr);
    if (!size) throw std::runtime_error("Invalid Unicode in connection settings");
    std::string result(size, '\0');
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, &result[0], size, nullptr, nullptr);
    result.pop_back();
    return result;
}

std::wstring Utf16(const std::string& text) {
    if (text.empty()) return {};
    int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), int(text.size()), nullptr, 0);
    if (!size) throw std::runtime_error("Invalid UTF-8 in JSON");
    std::wstring result(size, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), int(text.size()), &result[0], size);
    return result;
}

bool ReadJson(const std::string& text, Json::Value& value) {
    Json::CharReaderBuilder builder;
    builder["allowComments"] = false;
    builder["allowTrailingCommas"] = false;
    builder["stackLimit"] = 32;
    std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
    std::string errors;
    return reader->parse(text.data(), text.data() + text.size(), &value, &errors);
}

const unsigned short* JsonText(const std::string& text) {
    static std::wstring result; // JSON helpers run on the game thread.
    result = Utf16(text);
    return reinterpret_cast<const unsigned short*>(result.c_str());
}

void Queue(std::string packet) {
    std::lock_guard<std::mutex> lock(queueMutex);
    Json::Value commands;
    Json::Reader reader;
    if (reader.parse(packet, commands) && commands.isArray() && !commands.empty()) {
        const auto cmd = commands[0]["cmd"].asString();
        if (cmd == "RoomInfo") roomInfoPacket = packet;
        if (cmd == "NativeTransport") transportPacket = packet;
    }
    if (overflow) return;
    if (events.size() >= 512 || queuedBytes + packet.size() > 4 * 1024 * 1024) {
        overflow = true;
        events.clear();
        packet = "[{\"cmd\":\"NativeFatal\",\"reason\":\"AP event queue overflow\"}]";
        queuedBytes = 0;
    }
    queuedBytes += packet.size();
    events.push_back(std::move(packet));
}

void Error(const char* reason) {
    Json::Value packet;
    packet[0]["cmd"] = "NativeFatal";
    packet[0]["reason"] = reason;
    Json::FastWriter writer;
    Queue(writer.write(packet));
}

void FlushChecks() {
    if (!pendingChecks.empty()) {
        AP_SendItem(pendingChecks);
        pendingChecks.clear();
    }
}

void PollFrags() {
    if (!fragRequests[0]) return;
    for (const auto& request : fragRequests) {
        auto status = request->status.load();
        if (status == AP_RequestStatus::Pending) return;
        if (status == AP_RequestStatus::Error) {
            for (auto& reset : fragRequests) reset.reset();
            Error("Could not synchronize frag progress");
            return;
        }
    }
    Json::Value packet;
    packet[0]["cmd"] = "NativeFrags";
    for (int value : fragValues) packet[0]["values"].append(value);
    for (auto& request : fragRequests) request.reset();
    Json::FastWriter writer;
    Queue(writer.write(packet));
}

void StartFragSync() {
    if (!fragSyncRequested || fragRequests[0] ||
        AP_GetConnectionStatus() != AP_ConnectionStatus::Authenticated) return;
    fragSyncRequested = false;
    fragPrefix = AP_GetPrivateServerDataPrefix() + "UT99Frags";
    for (int i = 0; i < 82; ++i) {
        fragValues[i] = 0;
        fragRequests[i] = std::make_unique<AP_GetServerDataRequest>();
        fragRequests[i]->key = fragPrefix + std::to_string(i);
        fragRequests[i]->value = &fragValues[i];
        fragRequests[i]->type = AP_DataType::Int;
        AP_GetServerData(fragRequests[i].get());
    }
}

void StoredFrag(AP_SetReply reply) {
    if (fragPrefix.empty() || reply.key.compare(0, fragPrefix.size(), fragPrefix) != 0) return;
    auto suffix = reply.key.substr(fragPrefix.size());
    char* end = nullptr;
    long map = std::strtol(suffix.c_str(), &end, 10);
    Json::Value value;
    Json::Reader reader;
    if (!end || *end || map < 0 || map >= 82 || !reply.value ||
        !reader.parse(*static_cast<std::string*>(reply.value), value) || !value.isInt()) {
        Error("Invalid frag progress confirmation");
        return;
    }
    Json::Value packet;
    packet[0]["cmd"] = "NativeFragStored";
    packet[0]["map"] = int(map);
    packet[0]["value"] = value.asInt();
    Json::FastWriter writer;
    Queue(writer.write(packet));
}

void ShutdownSession() {
    if (sessionActive) AP_Shutdown();
    sessionActive = false;
    currentId = 0;
    activeUrl.clear(); activeSlot.clear(); activePassword.clear();
    pendingChecks.clear(); pendingScouts.clear();
    for (auto& request : fragRequests) request.reset();
    fragPrefix.clear();
    fragSyncRequested = false;
    std::lock_guard<std::mutex> lock(queueMutex);
    events.clear();
    queuedBytes = 0;
    overflow = false;
    roomInfoPacket.clear(); transportPacket.clear();
}
}

const unsigned short* JsonReadValue(const unsigned short* text, int& cursor, bool arrayElement) {
    try {
        if (cursor < 0 || size_t(cursor) > std::wcslen(reinterpret_cast<const wchar_t*>(text))) return nullptr;
        if (arrayElement) {
            if (cursor == 0) {
                if (text[0] != '[') return nullptr;
                cursor = 1;
            }
            while (text[cursor] && text[cursor] <= 32) ++cursor;
            if (text[cursor] == ',') ++cursor;
            while (text[cursor] && text[cursor] <= 32) ++cursor;
            if (!text[cursor] || text[cursor] == ']') return nullptr;
        }
        const auto input = Utf8(text + cursor);
        Json::Value value;
        if (!ReadJson(input, value)) return nullptr;
        const auto start = size_t(value.getOffsetStart()), end = size_t(value.getOffsetLimit());
        cursor += int(Utf16(input.substr(0, end)).size());
        return JsonText(input.substr(start, end - start));
    } catch (const std::exception&) { return nullptr; }
}

const unsigned short* JsonReadField(const unsigned short* text, const unsigned short* key) {
    try {
        const auto input = Utf8(text);
        Json::Value value;
        const auto name = Utf8(key);
        if (!ReadJson(input, value) || !value.isObject() || !value.isMember(name)) return JsonText("");
        const auto& field = value[name];
        const auto start = size_t(field.getOffsetStart()), end = size_t(field.getOffsetLimit());
        return JsonText(input.substr(start, end - start));
    } catch (const std::exception&) { return JsonText(""); }
}

const unsigned short* JsonReadString(const unsigned short* text) {
    try {
        const auto input = Utf8(text);
        Json::Value value;
        if (input.empty() || input[0] != '"') return JsonText(input);
        if (!ReadJson(input, value) || !value.isString()) return JsonText("");
        return JsonText(value.asString());
    } catch (const std::exception&) { return JsonText(""); }
}

int SessionOpen(const unsigned short* url, const unsigned short* slot, const unsigned short* password) {
    auto server = Utf8(url);
    auto name = Utf8(slot);
    auto secret = Utf8(password);
    bool queueOverflow;
    { std::lock_guard<std::mutex> lock(queueMutex); queueOverflow = overflow; }
    bool reuse = sessionActive && !queueOverflow && server == activeUrl && name == activeSlot &&
                 secret == activePassword && AP_GetConnectionStatus() != AP_ConnectionStatus::ConnectionRefused;
    if (sessionActive && !reuse) ShutdownSession();
    currentId = ++nextId;
    if (reuse) {
        pendingScouts.clear();
        {
            std::lock_guard<std::mutex> lock(queueMutex);
            events.clear();
            queuedBytes = 0;
            Json::Value bootstrap(Json::arrayValue), packet;
            Json::Reader reader;
            if (reader.parse(transportPacket, packet) && packet.isArray()) bootstrap.append(packet[0]);
            if (reader.parse(roomInfoPacket, packet) && packet.isArray()) bootstrap.append(packet[0]);
            if (!bootstrap.empty()) {
                Json::FastWriter writer;
                events.push_back(writer.write(bootstrap));
                queuedBytes = events.back().size();
            }
        }
        AP_RequestStateRefresh();
        return currentId;
    }
    try {
        AP_Init(server.c_str(), "Unreal Tournament 99", name.c_str(), secret.c_str());
        AP_NetworkVersion version{0, 6, 7};
        AP_SetClientVersion(&version);
        AP_EnableQueueItemRecvMsgs(false);
        AP_SetItemClearCallback([]{});
        AP_SetItemRecvCallback([](int64_t, int, bool){});
        AP_SetLocationCheckedCallback([](int64_t){});
        AP_SetLocationInfoCallback([](std::vector<AP_NetworkItem>){});
        AP_SetDeathLinkSupported(true);
        AP_SetDeathLinkRecvCallback([](std::string source, std::string cause) {
            Json::Value packet;
            packet[0]["cmd"] = "NativeDeathLink";
            packet[0]["source"] = source;
            packet[0]["cause"] = cause;
            Json::FastWriter writer;
            Queue(writer.write(packet));
            AP_DeathLinkClear();
        });
        AP_RegisterSetReplyCallback(StoredFrag);
        AP_SetNativePacketCallback([](std::string packet) {
            // Queue bytes only. No modification of game data.
            Queue(std::move(packet));
        });
        AP_Start();
        activeUrl = server; activeSlot = name; activePassword = secret;
        sessionActive = true;
    } catch (const std::exception& error) { AP_Shutdown(); Error(error.what()); }
    return currentId;
}

void SessionDetach(int id) {
    if (id && id == currentId) {
        currentId = 0;
        pendingScouts.clear();
    }
}

bool SessionSay(int id, const unsigned short* text) {
    if (!id || id != currentId || !text || text[0] != '!') return false;
    for (size_t i = 0; text[i]; ++i)
        if (i >= 400 || text[i] < 32 || text[i] == 127) return false;
    try {
        if (AP_GetConnectionStatus() != AP_ConnectionStatus::Authenticated) return false;
        AP_Say(Utf8(text));
        return true;
    } catch (const std::exception& error) { Error(error.what()); }
    return false;
}

void SessionClose(int id) {
    if (!id || id != currentId) return;
    ShutdownSession();
}

const unsigned short* SessionPoll(int id) {
    if (!id || id != currentId) return nullptr;
    try {
        StartFragSync();
        PollFrags();
        FlushChecks();
        if (!pendingScouts.empty()) {
            AP_SendLocationScouts(pendingScouts, 0);
            pendingScouts.clear();
        }
    } catch (const std::exception& error) { Error(error.what()); }
    std::string packet;
    {
        std::lock_guard<std::mutex> lock(queueMutex);
        if (!events.empty()) {
            packet = std::move(events.front());
            events.pop_front();
            queuedBytes -= packet.size();
        }
    }
    if (packet.empty()) {
        std::unique_ptr<AP_Message> message(AP_PopLatestMessage());
        if (!message) return nullptr;
        Json::Value chat;
        chat[0]["cmd"] = "NativeChat";
        chat[0]["text"] = message->text;
        chat[0]["command_result"] = message->type == AP_MessageType::CommandResult;
        for (const auto& part : message->messageParts) {
            Json::Value segment;
            segment["text"] = part.text;
            segment["kind"] = int(part.type);
            segment["flags"] = part.flags;
            segment["self"] = part.type == AP_PlayerText && part.player == AP_GetPlayerID();
            chat[0]["parts"].append(segment);
        }
        if (message->type == AP_MessageType::ItemSend) {
            chat[0]["item_notice"] = true;
            chat[0]["flags"] = static_cast<AP_ItemSendMessage*>(message.get())->flags;
        }
        Json::FastWriter writer;
        packet = writer.write(chat);
    }
    static std::wstring result; // Game-thread only. Bridge copies it.
    int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, packet.data(), int(packet.size()), nullptr, 0);
    if (!size) {
        result = L"[{\"cmd\":\"NativeFatal\",\"reason\":\"Invalid UTF-8 from AP\"}]";
    } else {
        result.resize(size);
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, packet.data(), int(packet.size()), &result[0], size);
    }
    return reinterpret_cast<const unsigned short*>(result.c_str());
}

void SessionCheck(int id, int location) {
    if (id && id == currentId) pendingChecks.insert(location);
}
void SessionScout(int id, int location) {
    if (id && id == currentId) pendingScouts.insert(location);
}
void SessionGoal(int id) {
    if (!id || id != currentId) return;
    try { FlushChecks(); AP_StoryComplete(); } catch (const std::exception& error) { Error(error.what()); }
}
void SessionDeath(int id) {
    if (!id || id != currentId || AP_GetConnectionStatus() != AP_ConnectionStatus::Authenticated) return;
    try { AP_DeathLinkSend(); } catch (const std::exception& error) { Error(error.what()); }
}
void SessionSync(int id) {
    if (!id || id != currentId) return;
    try { AP_RequestSync(); } catch (const std::exception& error) { Error(error.what()); }
}

bool SessionRequestFrags(int id) {
    if (!id || id != currentId) return false;
    fragSyncRequested = true;
    return true;
}

void SessionSetFrag(int id, int map, int value) {
    if (!id || id != currentId || map < 0 || map >= 82 || value < 0 || value > 100 ||
        fragPrefix.empty() || AP_GetConnectionStatus() != AP_ConnectionStatus::Authenticated) return;
    std::string raw = std::to_string(value), zero = "0";
    AP_DataStorageOperation operation{"max", &raw};
    AP_SetServerDataRequest request;
    request.key = fragPrefix + std::to_string(map);
    request.operations.push_back(operation);
    request.default_value = &zero;
    request.type = AP_DataType::Raw;
    request.want_reply = true;
    AP_SetServerData(&request);
}
