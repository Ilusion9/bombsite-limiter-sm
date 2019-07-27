#pragma semicolon 1 
#pragma newdecls required 

#include <sourcemod> 
#include <sdktools> 
#include <cstrike> 

public Plugin myinfo =
{
    name = "Bombsite Locker",
    author = "Ilusion9",
    description = "Disable bombsites if there are fewer CTs than the accepted limit",
    version = "1.1",
    url = "https://github.com/Ilusion9/"
};

ArrayList g_BombSites;
StringMap g_Configuration;

public void OnPluginStart() 
{
	LoadTranslations("bombsites.phrases");
	
	g_BombSites = new ArrayList();
	g_Configuration = new StringMap();
	
	HookEvent("round_freeze_end", Event_RoundFreezeEnd);
}

public void OnMapStart()
{	
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
	{
		g_BombSites.Push(ent);
	}
	
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	KeyValues kv = new KeyValues("BombSites"); 

	GetCurrentMap(map, sizeof(map));
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsites.cfg");
	
	if (!kv.ImportFromFile(path)) 
	{
		SetFailState("The configuration file could not be read.");
	}
	
	if (kv.JumpToKey(map)) 
	{
		if (kv.GotoFirstSubKey(false))
		{
			do 
			{
				char key[64];
				kv.GetSectionName(key, sizeof(key));
				
				if (key[1] || !IsCharAlpha(key[0]))
				{
					LogError("The configuration file is corrupt (The bomb site must be an alphabetical character).");
					continue;
				}
				
				key[0] = CharToUpper(key[0]);
				
				if (key[0] - 65 >= g_BombSites.Length)
				{
					LogError("There is no site %c available for this map.", key[0]);
					continue;
				}
				
				Format(key, sizeof(key), "%c", key[0]);
				g_Configuration.SetValue(key, kv.GetNum(NULL_STRING, 0));
				
			} while (kv.GotoNextKey(false));
		}
	}
	
	delete kv;
}

public void OnMapEnd()
{
	g_BombSites.Clear();
	g_Configuration.Clear();
}

public void OnConfigsExecuted()
{
	if (g_Configuration.Size)
	{
		ConVar cvar = FindConVar("mp_join_grace_time"); 

		if (cvar)
		{
			cvar.IntValue = 0; 
		}
	}
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) 
{
	if (g_Configuration.Size)
	{
		int numCT = GetTeamClientCount(CS_TEAM_CT);
		
		for (int i = 0; i < g_BombSites.Length; i++)
		{
			int value;

			char key[64];
			Format(key, sizeof(key), "%c", i + 65);
			
			if (g_Configuration.GetValue(key, value))
			{
				if (numCT < value)
				{
					AcceptEntityInput(g_BombSites.Get(i), "Disable");
					CPrintToChatAll("%t", "Bombsite Disabled", key, key);
					
					continue;
				}
			}
			
			AcceptEntityInput(g_BombSites.Get(i), "Enable");
		}
	}
}

void CPrintToChatAll(const char[] format, any ...)
{
	char buffer[254];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SetGlobalTransTarget(i);
			VFormat(buffer, sizeof(buffer), format, 2);
			
			ReplaceColors(buffer, sizeof(buffer));
			PrintToChat(i, " %s", buffer);
		}
	}
}

char g_ColorsTrans[][] = {"{NORMAL}", "{DARKRED}", "{PINK}", "{GREEN}", "{YELLOW}", "{LIGHTGREEN}", "{RED}", "{GRAY}",  "{BLUE}", "{DARKBLUE}", "{PURPLE}",  "{ORANGE}"};
char g_ColorsHex[][] = {"\x01", "\x02", "\x03", "\x04", "\x09", "\x06", "\x07", "\x08", "\x0B", "\x0C", "\x0E", "\x10"};

void ReplaceColors(char[] buffer, int maxlen)
{
	for (int i = 0; i < sizeof(g_ColorsTrans); i++)
	{
		ReplaceString(buffer, maxlen, g_ColorsTrans[i], g_ColorsHex[i]);
	}
}