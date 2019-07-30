#pragma semicolon 1 
#pragma newdecls required 

#include <sourcemod> 
#include <sdktools> 
#include <cstrike> 

public Plugin myinfo =
{
    name = "Bombsite Limiter",
    author = "Ilusion9",
    description = "Disable bombsites if there are fewer CTs than the accepted limit",
    version = "2.0",
    url = "https://github.com/Ilusion9/"
};

StringMap g_Configuration;

public void OnPluginStart() 
{
	/* Load translation file */
	LoadTranslations("bombsites.phrases");
	
	/* Map variable constructor */
	g_Configuration = new StringMap();
	
	/* Hook game events */
	HookEvent("round_freeze_end", Event_RoundFreezeEnd);
}

public void OnConfigsExecuted()
{
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	KeyValues kv = new KeyValues("BombSites"); 

	/* Get the current map name */
	GetCurrentMap(map, sizeof(map));
	
	/* Build a path to the configuration file */
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsites.cfg");
	
	/* Open the configuration file */
	if (!kv.ImportFromFile(path)) 
	{
		SetFailState("The configuration file could not be read.");
	}
	
	/* Jump to the current map configuration */
	if (kv.JumpToKey(map)) 
	{
		if (kv.GotoFirstSubKey(false))
		{
			do 
			{
				char key[64];
				kv.GetSectionName(key, sizeof(key));			
				g_Configuration.SetValue(key, kv.GetNum(NULL_STRING, 0));
				
			} while (kv.GotoNextKey(false));
		}
	}
	
	/* Clear out the memory */
	delete kv;
	
	if (g_Configuration.Size)
	{
		/* Players should not spawn after the freeze time ends */
		ConVar cvar = FindConVar("mp_join_grace_time"); 

		if (cvar)
		{
			cvar.IntValue = 0; 
		}
	}
}

public void OnMapEnd()
{
	g_Configuration.Clear();
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) 
{
	if (g_Configuration.Size)
	{
		int siteA = -1, siteB = -1, siteC = -1;
		
		/* Find player manager entity */
		int ent = FindEntityByClassname(-1, "cs_player_manager");
		
		if (ent != -1)
		{
			float posA[3], posB[3];
			
			/* Bombisite A origin */
			GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterA", posA); 
			
			/* Bombisite B origin */
			GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterB", posB);
			
			/* Loop through all bombsites */
			ent = -1;
			while ((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
			{
				float vecMins[3], vecMaxs[3];
				
				GetEntPropVector(ent, Prop_Send,"m_vecMins", vecMins); 
				GetEntPropVector(ent, Prop_Send,"m_vecMaxs", vecMaxs);
				
				/* Check if this bombsite is A */
				if (IsVecBetween(posA, vecMins, vecMaxs)) 
				{
					siteA = ent; 
				}
				
				/* Check if this bombsite is B */
				else if (IsVecBetween(posB, vecMins, vecMaxs)) 
				{
					siteB = ent; 
				}
				
				/* Bombsite C */
				else
				{
					if (siteC != -1) continue;
					siteC = ent;
				}
				
				/* Enable all bombsites */
				AcceptEntityInput(ent, "Enable");
			}
		}
		
		int value;
		int numCT = GetCounterTerroristsCount();
		
		/* Limit bombsite A */
		if (siteA != -1)
		{			
			if (g_Configuration.GetValue("A", value))
			{
				if (numCT < value)
				{
					AcceptEntityInput(siteA, "Disable");
					PrintToChatAll(" \x04[SITE A]\x01 %t", "Bombsite Disabled", "\x04A\x01");
				}
			}
		}
		
		/* Limit bombsite B */
		if (siteB != -1)
		{
			if (g_Configuration.GetValue("B", value))
			{
				if (numCT < value)
				{
					AcceptEntityInput(siteB, "Disable");
					PrintToChatAll(" \x04[SITE B]\x01 %t", "Bombsite Disabled", "\x04B\x01");
				}
			}
		}
		
		/* Limit bombsite C */
		if (siteC != -1)
		{
			if (g_Configuration.GetValue("C", value))
			{
				if (numCT < value)
				{
					AcceptEntityInput(siteC, "Disable");
					PrintToChatAll(" \x04[SITE C]\x01 %t", "Bombsite Disabled", "\x04C\x01");
				}
			}
		}
	}
}

stock bool IsVecBetween(const float vecVector[3], const float vecMin[3], const float vecMax[3]) 
{
	return ((vecMin[0] <= vecVector[0] <= vecMax[0]) && (vecMin[1] <= vecVector[1] <= vecMax[1]) && (vecMin[2] <= vecVector[2] <= vecMax[2])); 
}

stock int GetCounterTerroristsCount()
{
	int num;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_CT)
		{
			num++;
		}
	}
	
	return num;
}