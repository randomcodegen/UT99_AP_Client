#include <chrono>
#include <iostream>
#include <thread>
#include <json/json.h>
#include <ixwebsocket/IXWebSocket.h>
#include "Session.h"

extern ix::WebSocket webSocket;

int wmain(int argc, wchar_t** argv) {
    if (argc < 4 || argc > 5) return 2; // URL, CA file, expected TLS/ws/reject, [reattach]
    std::wstring ca = argv[2];
    ix::SocketTLSOptions tls;
    tls.caFile.assign(ca.begin(), ca.end()); 
    webSocket.setTLSOptions(tls);
    auto wide = [](const wchar_t* p) { return reinterpret_cast<const unsigned short*>(p); };
    int previous = SessionOpen(wide(L"ws://127.0.0.1:1"), wide(L"OldSlot"), wide(L""));
    int id = SessionOpen(wide(argv[1]), wide(L"NativeTLS"), wide(L""));
    SessionClose(previous); // A stale object must not close the new session
    if (SessionSay(previous, wide(L"!help")) || SessionSay(0, wide(L"!help"))) return 6;
    bool connected = false, inventory = false, checked = false, sent = false, rejected = false, chat = false;
    bool reattached = false;
    std::wstring expected = argv[3];
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(18);
    while (std::chrono::steady_clock::now() < deadline) {
        if (const auto* event = SessionPoll(id)) {
            std::wstring text(reinterpret_cast<const wchar_t*>(event));
            std::string json(text.begin(), text.end());
            std::cout << json << std::flush;
            Json::Value packets;
            Json::Reader reader;
            if (!reader.parse(json, packets)) return 3;
            for (const auto& packet : packets) {
                auto cmd = packet["cmd"].asString();
                if (cmd == "NativeTransport") {
                    bool secure = packet["url"].asString().find("wss://") == 0;
                    if ((expected == L"TLS" && !secure) || expected == L"reject") return 4;
                    if (expected == L"ws" && secure) return 5;
                }
                if (cmd == "NativeDisconnected") {
                    auto reason = packet["reason"].asString();
                    if (reason.find("certificate") != std::string::npos || reason.find("Certificate") != std::string::npos)
                        rejected = true;
                }
                if (cmd == "Connected") connected = true;
                if (cmd == "ReceivedItems") inventory = true;
                if (cmd == "NativeChat") chat = true;
                if (cmd == "RoomUpdate" && packet["checked_locations"].size()) checked = true;
            }
            if (connected && inventory && !sent) {
                if (argc == 5 && !reattached) {
                    int old = id;
                    SessionDetach(id);
                    id = SessionOpen(wide(argv[1]), wide(L"NativeTLS"), wide(L""));
                    if (id == old || SessionSay(old, wide(L"!help"))) return 10;
                    connected = inventory = false;
                    reattached = true;
                    continue;
                }
                if (SessionSay(previous, wide(L"!help")) || SessionSay(id, wide(L"ordinary UT command")) ||
                    SessionSay(id, wide(L"!hint bad\nname")) || SessionSay(id, wide((L"!" + std::wstring(400, L'x')).c_str()))) return 7;
                if (!SessionSay(id, wide(L"!help")) || !SessionSay(id, wide(L"!hint Shock Rifle \"Unlock\" \\ \u00fc")) ||
                    !SessionSay(id, wide(L"!hint_location DM-Oblivion - Pickup MiniAmmo0"))) return 8;
                SessionCheck(id, 19991001);
                SessionGoal(id);
                sent = true;
            }
            if ((checked && chat) || (expected == L"reject" && rejected)) break;
        } else std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    SessionClose(id);
    if (SessionSay(id, wide(L"!help"))) return 9;
    SessionClose(id);
    if ((expected == L"reject" && rejected && !connected) || (expected != L"reject" && checked && chat)) {
        std::cout << "NATIVE SESSION PASS\n";
        return 0;
    }
    return 1;
}
