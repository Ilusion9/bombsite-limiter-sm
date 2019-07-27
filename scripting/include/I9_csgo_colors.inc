char g_TranslationColors[][] = {"{NORMAL}", "{DARKRED}", "{PINK}", "{GREEN}", "{YELLOW}", "{LIGHTGREEN}", "{RED}", "{GRAY}", "{BLUE}", "{DARKBLUE}", "{PURPLE}", "{ORANGE}"};
char g_HexColors[][] = {"\x01", "\x02", "\x03", "\x04", "\x09", "\x06", "\x07", "\x08", "\x0B", "\x0C", "\x0E", "\x10"};

stock void CPrintToChat(int client, const char[] format, any ...)
{
	if (client < 1 || client > MaxClients)
	{
		ThrowError("Invalid client index %d", client);
	}
	
	if (!IsClientInGame(client))
	{
		ThrowError("Client %d is not in game", client);
	}
	
	char buffer[254];
	SetGlobalTransTarget(client);
	
	VFormat(buffer, sizeof(buffer), format, 3);
	TranslateColors(buffer, sizeof(buffer));
	
	PrintToChat(client, " %s", buffer);
}

stock void CPrintToChatAll(const char[] format, any ...)
{
	char buffer[254];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SetGlobalTransTarget(i);
			VFormat(buffer, sizeof(buffer), format, 2);
			CPrintToChat(i, " %s", buffer);
		}
	}
}

stock void TranslateColors(char[] buffer, int maxlen)
{
	for (int i = 0; i < sizeof(g_TranslationColors); i++)
	{
		ReplaceString(buffer, maxlen, g_TranslationColors[i], g_HexColors[i]);
	}
}