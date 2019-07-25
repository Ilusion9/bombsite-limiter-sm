#pragma semicolon 1 
#pragma newdecls required 

#include <sourcemod> 
#include <sdktools> 
#include <cstrike> 

public Plugin myinfo =
{
    name = "Bombsite Locker",
    author = "Ilusion9",
    description = "Enable only one site if there are fewer CTs than the accepted limit",
    version = "1.0",
    url = "https://github.com/Ilusion9/"
};

ArrayList g_Sites;

bool g_MapConfig;

int g_EnabledSite;
int g_MinCTPlayers;

public void OnPluginStart() 
{
	/* Load translation file */
	LoadTranslations("bombsites.phrases");
	
	/* Arraylist constructor */
	g_Sites = new ArrayList();
	
	/* Hook game events */
	HookEvent("round_freeze_end", Event_RoundFreezeEnd);
}

public void OnMapStart()
{
	g_MapConfig = false;
	
	/* Find all bomb sites of this map */
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
	{
		g_Sites.Push(ent);
	}
	
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	KeyValues kv = new KeyValues("BombSites"); 

	GetCurrentMap(map, sizeof(map));
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsites.cfg");
	
	/* Open the configuration file */
	if (!kv.ImportFromFile(path)) 
	{
		SetFailState("The configuration file could not be read.");
	}
	
	/* Get the configuration for this map */
	if (kv.JumpToKey(map)) 
	{	
		g_MapConfig = true;
		char value[128];
		
		/* Get the available bomb site */
		kv.GetString("enabled_site", value, sizeof(value));
		
		if (IsCharAlpha(value[0]))
		{
			g_EnabledSite = IsCharUpper(value[0]) ? (value[0] - 65) : (value[0] - 97);
			
			if (g_EnabledSite >= g_Sites.Length)
			{
				LogError("There is no site %c available for this map.", g_EnabledSite + 65);
				g_MapConfig = false;
			}
		}
		else
		{
			LogError("The configuration file is corrupt (\"enabled_site\" value must be an alphabetical character).");
			g_MapConfig = false;
		}
		
		/* Get the CTs limit for this map to enable only one site */
		kv.GetString("ct_limit", value, sizeof(value));
		
		if (!StringToIntEx(value, g_MinCTPlayers))
		{
			LogError("The configuration file is corrupt (\"ct_limit\" value must be a numerical character).");
			g_MapConfig = false;
		}
	}
	
	delete kv;
}

public void OnMapEnd()
{
	g_Sites.Clear();
}

public void OnConfigsExecuted()
{
	if (g_MapConfig)
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
	/* Check if this map has a valid configuration */
	if (!g_MapConfig) return;
	
	/* Get the number of CT players */
	int numCT = GetTeamClientCount(CS_TEAM_CT);
	
	/* Enable only one site if there are fewer CTs than the limit */
	if (numCT && numCT < g_MinCTPlayers)
	{
		PrintToChatAll("%t", "Only One Site", g_EnabledSite + 65);
		PrintToChatAll("%t", "Only One Site", g_EnabledSite + 65);
		PrintToChatAll("%t", "Only One Site", g_EnabledSite + 65);
		PrintToChatAll("%t", "Only One Site", g_EnabledSite + 65);
		PrintToChatAll("%t", "Only One Site", g_EnabledSite + 65);

		PrintHintTextToAll("%t", "Only One Site", g_EnabledSite + 65);
		
		for (int i = 0; i < g_Sites.Length; i++)
		{
			if (i != g_EnabledSite)
			{
				AcceptEntityInput(g_Sites.Get(i), "Disable");
			}
		}
	}
	else
	{
		for (int i = 0; i < g_Sites.Length; i++)
		{
			AcceptEntityInput(g_Sites.Get(i), "Enable");
		}
	}
}
