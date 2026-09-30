#pragma once
// UTF-16 primitives avoid UE1's incompatible wchar
int SessionOpen(const unsigned short* url, const unsigned short* slot, const unsigned short* password);
void SessionDetach(int id);
void SessionClose(int id);
const unsigned short* SessionPoll(int id);
void SessionCheck(int id, int location);
void SessionScout(int id, int location);
void SessionGoal(int id);
void SessionDeath(int id);
void SessionSync(int id);
bool SessionSay(int id, const unsigned short* text);
bool SessionRequestFrags(int id);
void SessionSetFrag(int id, int map, int value);
const unsigned short* JsonReadValue(const unsigned short* text, int& cursor, bool arrayElement);
const unsigned short* JsonReadField(const unsigned short* text, const unsigned short* key);
const unsigned short* JsonReadString(const unsigned short* text);
